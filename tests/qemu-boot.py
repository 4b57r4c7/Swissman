#!/usr/bin/env python3
"""Boot Swissman in QEMU with UEFI firmware and check the running system.

Usage:
  qemu-boot.py live <iso> [--secure-boot <vars>] [--timeout <seconds>]
  qemu-boot.py encrypted <kernel> <disk> <luks-uuid> <passphrase> [--timeout <seconds>]
  qemu-boot.py rejected <iso> --secure-boot <vars> [--timeout <seconds>]
  qemu-boot.py fido2 <kernel> <disk> <luks-uuid> <passphrase> <hidraw> [--timeout <seconds>]
  qemu-boot.py install <iso> <disk> <hidraw> <update-url> <update-key.pem> [--timeout <seconds>]

live: boots the ISO, waits for the live system to log root in on the
serial console, then runs the checks in CHECKS there. With --secure-boot,
the firmware enforces Secure Boot with the keys enrolled in the given
variable store (see make-secureboot-vars.sh), and the live system must
report Secure Boot as enabled.

rejected: with Secure Boot enforced by a variable store that trusts other
keys than the ones the ISO was signed with, the firmware must refuse to
start the ISO's boot loader.

encrypted: boots the kernel on its own against a disk made by
make-encrypted-disk.sh, the way an installed system boots. It first
enters a wrong passphrase, which must be refused, then the right one,
and waits for the login prompt of the system on the encrypted disk.

fido2: the disk also has a FIDO2 security key enrolled (enroll-fido2.sh).
The host's key, given as its hidraw device, is passed through to the
machine, which must unlock the disk with it without asking for the
passphrase. Then it boots again without the key, and the passphrase must
still unlock the disk.

install: the whole life of an installed system, on a machine whose
firmware starts in Secure Boot Setup Mode (no keys enrolled) and keeps its
variables across starts:
 1. boots the ISO and runs swissman-install onto the empty <disk>, with
    the host's FIDO2 key (<hidraw>) passed through and enrolled;
 2. starts from the disk alone: Secure Boot must now be enforced with the
    machine's own keys, the security key must unlock the disk, and the new
    user and root must log in with their passwords. As root it trusts
    <update-key.pem>, checks that an update signed by another key is
    refused (<update-url>/bad), and stages <update-url>/good;
 3. starts without the security key, unlocks with the passphrase, and
    checks that the update was switched to; then rolls it back;
 4. starts again and checks that the rollback was switched to.
<update-url> is seen from inside the machine (the host is 10.0.2.2).

The serial console is copied to stdout and to out/boot-<mode>.log. Exits 0
on success, 1 on a kernel panic, an initramfs rescue shell, a failed check
or a timeout.
"""
import argparse
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_CODE_SECBOOT = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
OVMF_VARS = "/usr/share/OVMF/OVMF_VARS_4M.fd"
FAILURES = [b"Kernel panic", b"rescue shell", b"Failed to start Switch Root"]
CHECK_TIMEOUT = 120

# Shell commands run on the booted live system, by name. A check passes
# when its command succeeds. The marker is quoted so the echoed command
# line itself does not match.
CHECKS = {
    "firewall": "systemctl is-active -q nftables && "
                "nft list chain inet filter input | grep -q 'policy drop'",
    "sysctl": "[ \"$(sysctl -n kernel.kptr_restrict)\" = 2 ] && "
              "[ \"$(sysctl -n kernel.yama.ptrace_scope)\" = 2 ]",
    "lockdown": "grep -q '\\[integrity\\]' /sys/kernel/security/lockdown",
}
# The last byte of the SecureBoot variable is 1 when it is enforced.
SECURE_BOOT_CHECK = ("[ \"$(od -An -tu1 /sys/firmware/efi/efivars/"
                     "SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c "
                     "| awk '{print $NF}')\" = 1 ]")


class Machine:
    def __init__(self, args, log_path, secure_boot_vars=None, persistent_vars=None):
        """persistent_vars: a Secure Boot capable variable store used in
        place, so changes survive into the next Machine."""
        if persistent_vars:
            vars_copy = persistent_vars
        else:
            vars_copy = tempfile.NamedTemporaryFile(suffix=".fd", delete=False).name
            shutil.copy(secure_boot_vars or OVMF_VARS, vars_copy)
        if secure_boot_vars or persistent_vars:
            # The Secure Boot firmware keeps its variables in SMM.
            machine = ["-machine", "q35,smm=on",
                       "-global", "driver=cfi.pflash01,property=secure,value=on"]
            code = OVMF_CODE_SECBOOT
        else:
            machine = ["-machine", "q35"]
            code = OVMF_CODE
        cmd = ["qemu-system-x86_64"] + machine + ["-m", "2048", "-smp", "2",
               "-nographic", "-no-reboot",
               "-drive", f"if=pflash,format=raw,readonly=on,file={code}",
               "-drive", f"if=pflash,format=raw,file={vars_copy}"] + args
        if os.access("/dev/kvm", os.R_OK | os.W_OK):
            cmd[1:1] = ["-enable-kvm", "-cpu", "host"]
        else:
            print("KVM not available, using emulation (slow)", flush=True)
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
        self.log = open(log_path, "wb")
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT)
        os.set_blocking(self.proc.stdout.fileno(), False)
        self.seen = b""

    def wait_for(self, done, timeout):
        """Copy console output until done(seen) is true; return an error or None."""
        deadline = time.time() + timeout
        while not done(self.seen):
            if time.time() > deadline:
                return "timeout"
            chunk = self.proc.stdout.read()
            if chunk:
                sys.stdout.buffer.write(chunk)
                sys.stdout.flush()
                self.log.write(chunk)
                self.seen = (self.seen + chunk)[-65536:]
                for f in FAILURES:
                    if f in self.seen:
                        return f"saw '{f.decode()}'"
            elif self.proc.poll() is not None:
                return f"QEMU exited with {self.proc.returncode}"
            else:
                time.sleep(0.2)
        return None

    def expect(self, text, timeout):
        return self.wait_for(lambda s: text in s, timeout)

    def send(self, line):
        self.proc.stdin.write(line.encode() + b"\n")
        self.proc.stdin.flush()

    def forget(self):
        """Ignore the output seen so far in later waits."""
        self.seen = b""

    def kill(self):
        self.proc.kill()

    def run_checks(self, checks, timeout=CHECK_TIMEOUT):
        """Run shell checks (name -> command) at a shell prompt; return an
        error or None."""
        self.forget()
        for name, check in checks.items():
            self.send(f"if {check}; then echo CHECK-'{name}'-ok; "
                      f"else echo CHECK-'{name}'-failed; fi")
            time.sleep(0.5)
        markers = [f"CHECK-{n}-".encode() for n in checks]
        error = self.wait_for(lambda s: all(m in s for m in markers), timeout)
        failed = [n for n in checks if f"CHECK-{n}-ok".encode() not in self.seen]
        if error:
            return f"{error} while running checks"
        if failed:
            return f"checks failed: {', '.join(failed)}"
        return None

    def login(self, user, password, timeout):
        error = self.expect(b"login:", timeout)
        if error:
            return f"{error} before the login prompt"
        self.forget()
        self.send(user)
        error = self.expect(b"Password:", CHECK_TIMEOUT)
        if error:
            return f"{error} before the password prompt"
        self.send(password)
        time.sleep(3)  # let the shell start
        return None

    def power_off(self, timeout=CHECK_TIMEOUT):
        self.send("poweroff")
        try:
            self.proc.wait(timeout)
        except subprocess.TimeoutExpired:
            self.kill()


def test_live(iso, timeout, secure_boot_vars=None):
    checks = dict(CHECKS)
    if secure_boot_vars:
        checks["secureboot"] = SECURE_BOOT_CHECK
    log = "out/boot-live-secureboot.log" if secure_boot_vars else "out/boot-live.log"
    vm = Machine(["-cdrom", iso], log, secure_boot_vars)
    try:
        error = vm.expect(b"(automatic login)", timeout)
        if error:
            return f"{error} before the automatic login", False
        time.sleep(3)  # let the shell start
        error = vm.run_checks(checks)
        if error:
            return error, False
        return f"all checks passed: {', '.join(checks)}", True
    finally:
        vm.kill()


def test_encrypted(kernel, disk, uuid, passphrase, timeout):
    vm = Machine(["-kernel", kernel, "-append", f"swissman.root=UUID={uuid}",
                  "-drive", f"if=virtio,format=raw,file={disk}"],
                 "out/boot-encrypted.log")
    try:
        prompt = b"Enter passphrase"
        error = vm.expect(prompt, timeout)
        if error:
            return f"{error} before the passphrase prompt", False
        vm.forget()
        vm.send("not-the-passphrase")
        error = vm.expect(b"No key available with this passphrase", CHECK_TIMEOUT)
        if error:
            return f"{error}: a wrong passphrase was not refused", False
        error = vm.expect(prompt, CHECK_TIMEOUT)
        if error:
            return f"{error} before the second passphrase prompt", False
        vm.forget()
        vm.send(passphrase)
        error = vm.expect(b"login:", timeout)
        if error:
            return f"{error} after unlocking the disk", False
        return "unlocked the encrypted root and reached the login prompt", True
    finally:
        vm.kill()


def test_fido2(kernel, disk, uuid, passphrase, hidraw, timeout):
    base = ["-kernel", kernel, "-append", f"swissman.root=UUID={uuid}",
            "-drive", f"if=virtio,format=raw,file={disk}"]
    key = ["-device", "qemu-xhci", "-device", f"u2f-passthru,hidraw={hidraw}"]
    asked = b"passphrase for disk"

    vm = Machine(base + key, "out/boot-fido2.log")
    try:
        error = vm.wait_for(lambda s: b"login:" in s or asked in s, timeout)
        if error:
            return f"{error} before unlocking with the security key", False
        if asked in vm.seen:
            return "asked for the passphrase although the security key was present", False
    finally:
        vm.kill()

    vm = Machine(base, "out/boot-fido2-fallback.log")
    try:
        error = vm.expect(asked, timeout)
        if error:
            return f"{error} before the passphrase prompt without the key", False
        vm.forget()
        vm.send(passphrase)
        error = vm.expect(b"login:", timeout)
        if error:
            return f"{error} after typing the passphrase without the key", False
    finally:
        vm.kill()
    return "unlocked with the security key, and with the passphrase without it", True


def test_rejected(iso, timeout, secure_boot_vars):
    vm = Machine(["-cdrom", iso], "out/boot-rejected.log", secure_boot_vars)
    try:
        # OVMF reports the refused image and moves on to the next boot
        # option; the kernel must never start.
        error = vm.wait_for(lambda s: b"Access Denied" in s or b"Linux version" in s,
                            timeout)
        if error:
            return f"{error} waiting for the firmware to refuse the image", False
        if b"Linux version" in vm.seen:
            return "the firmware started a kernel signed by an unknown key", False
        return "the firmware refused a boot loader signed by an unknown key", True
    finally:
        vm.kill()


def test_install(iso, disk, hidraw, update_url, update_key, timeout):
    passphrase = "disk-" + os.urandom(6).hex()
    root_pw, user_pw = "root-" + os.urandom(6).hex(), "user-" + os.urandom(6).hex()
    with open(update_key, "rb") as f:
        key_b64 = base64.b64encode(f.read()).decode()
    nvram = tempfile.NamedTemporaryFile(suffix=".fd", delete=False).name
    shutil.copy(OVMF_VARS, nvram)  # no keys: Setup Mode
    drive = ["-drive", f"if=virtio,format=raw,file={disk}"]
    key = ["-device", "qemu-xhci", "-device", f"u2f-passthru,hidraw={hidraw}"]
    net = ["-nic", "user,model=virtio-net-pci"]

    # 1. Install from the live ISO.
    vm = Machine(["-cdrom", iso] + drive + key, "out/boot-install-1.log", persistent_vars=nvram)
    try:
        error = vm.expect(b"(automatic login)", timeout)
        if error:
            return f"{error} before the live system logged in", False
        time.sleep(3)
        vm.forget()
        vm.send(f"SWISSMAN_DISK_PASSPHRASE={passphrase} SWISSMAN_ROOT_PASSWORD={root_pw} "
                f"SWISSMAN_USER_PASSWORD={user_pw} swissman-install --disk /dev/vda "
                "--hostname testbox --user tester --fido2 presence --serial-console --yes; "
                "echo INSTALL-'EXIT'-$?")
        error = vm.wait_for(lambda s: re.search(rb"INSTALL-EXIT-[0-9]", s), timeout)
        if error:
            return f"{error} while installing", False
        if b"INSTALL-EXIT-0" not in vm.seen:
            return "swissman-install failed", False
        if b"Secure Boot keys enrolled" not in vm.seen:
            return "swissman-install did not enroll the Secure Boot keys", False
        vm.power_off()
    finally:
        vm.kill()

    # 2. Start the installed system with the security key.
    vm = Machine(drive + key + net, "out/boot-install-2.log", persistent_vars=nvram)
    try:
        error = vm.wait_for(lambda s: b"login:" in s or b"passphrase for disk" in s, timeout)
        if error:
            return f"{error} starting the installed system", False
        if b"passphrase for disk" in vm.seen:
            return "asked for the passphrase although the security key was present", False
        error = vm.login("tester", user_pw, timeout) or vm.run_checks({
            "user": "[ \"$(id -un)\" = tester ]",
            "hostname": "[ \"$(cat /proc/sys/kernel/hostname)\" = testbox ]",
            "secureboot": SECURE_BOOT_CHECK,
            "firewall": "[ -f /etc/nftables.conf ]",
        })
        if error:
            return f"as the user: {error}", False
        vm.forget()
        vm.send("exit")
        error = vm.login("root", root_pw, timeout) or vm.run_checks({
            "root": "[ \"$(id -u)\" = 0 ]",
            "fido2-enrolled": "cryptsetup luksDump /dev/vda2 | grep -q systemd-fido2",
            "esp": "[ -f /efi/EFI/Linux/swissman.efi ]",
            "trust-test-key": "mkdir -p /etc/swissman/update-keys && "
                              f"echo {key_b64} | base64 -d > /etc/swissman/update-keys/test.pem",
            "network": "for i in $(seq 60); do ip route | grep -q default && break; sleep 1; done; "
                       "ip route | grep -q default",
            "refuse-bad-signature": f"swissman-update --url {update_url}/bad 2>&1 "
                                    "| grep -q 'not signed by a trusted key' && [ ! -d /usr.new ]",
            "stage-update": f"swissman-update --url {update_url}/good && [ -d /usr.new ] && "
                            "[ -f /efi/EFI/Linux/swissman-previous.efi ]",
        }, timeout=600)
        if error:
            return f"as root: {error}", False
        vm.power_off()
    finally:
        vm.kill()

    # 3. Start without the security key; the update is switched to.
    vm = Machine(drive + net, "out/boot-install-3.log", persistent_vars=nvram)
    try:
        error = vm.expect(b"passphrase for disk", timeout)
        if error:
            return f"{error} before the passphrase prompt without the key", False
        vm.forget()
        vm.send(passphrase)
        error = vm.login("root", root_pw, timeout) or vm.run_checks({
            "updated": "[ \"$(cat /var/lib/swissman/version)\" = 999.0.0 ] && [ -d /usr.old ]",
            "secureboot": SECURE_BOOT_CHECK,
            "rollback": "swissman-update --rollback && [ -d /usr.new ]",
        })
        if error:
            return f"after the update: {error}", False
        vm.power_off()
    finally:
        vm.kill()

    # 4. The rollback is switched to.
    vm = Machine(drive, "out/boot-install-4.log", persistent_vars=nvram)
    try:
        error = vm.expect(b"passphrase for disk", timeout)
        if error:
            return f"{error} before the passphrase prompt after the rollback", False
        vm.forget()
        vm.send(passphrase)
        error = vm.login("root", root_pw, timeout) or vm.run_checks({
            "rolled-back": "[ \"$(cat /var/lib/swissman/version)\" != 999.0.0 ] && "
                           "[ \"$(cat /var/lib/swissman/previous-version)\" = 999.0.0 ]",
            "secureboot": SECURE_BOOT_CHECK,
        })
        if error:
            return f"after the rollback: {error}", False
    finally:
        vm.kill()
    return ("installed, booted with Secure Boot and the security key, logged in, "
            "refused a badly signed update, updated and rolled back"), True


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("mode", choices=["live", "encrypted", "fido2", "rejected", "install"])
    parser.add_argument("args", nargs="+")
    parser.add_argument("--secure-boot", metavar="VARS")
    parser.add_argument("--timeout", type=int, default=900)
    opts = parser.parse_args()
    if opts.mode == "live":
        message, ok = test_live(*opts.args, opts.timeout, opts.secure_boot)
    elif opts.mode == "encrypted":
        message, ok = test_encrypted(*opts.args, opts.timeout)
    elif opts.mode == "fido2":
        message, ok = test_fido2(*opts.args, opts.timeout)
    elif opts.mode == "install":
        message, ok = test_install(*opts.args, opts.timeout)
    else:
        if not opts.secure_boot:
            parser.error("rejected needs --secure-boot")
        message, ok = test_rejected(*opts.args, opts.timeout, opts.secure_boot)
    print(f"\n==> Boot test ({opts.mode}): {message}", flush=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
