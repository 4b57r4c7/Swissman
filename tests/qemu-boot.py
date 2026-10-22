#!/usr/bin/env python3
"""Boot Swissman in QEMU with UEFI firmware and check the running system.

Usage:
  qemu-boot.py live <iso> [--secure-boot <vars>] [--timeout <seconds>]
  qemu-boot.py encrypted <kernel> <disk> <luks-uuid> <passphrase> [--timeout <seconds>]
  qemu-boot.py rejected <iso> --secure-boot <vars> [--timeout <seconds>]

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

The serial console is copied to stdout and to out/boot-<mode>.log. Exits 0
on success, 1 on a kernel panic, an initramfs rescue shell, a failed check
or a timeout.
"""
import argparse
import os
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
    def __init__(self, args, log_path, secure_boot_vars=None):
        vars_copy = tempfile.NamedTemporaryFile(suffix=".fd", delete=False).name
        shutil.copy(secure_boot_vars or OVMF_VARS, vars_copy)
        if secure_boot_vars:
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
        vm.forget()
        for name, check in checks.items():
            vm.send(f"if {check}; then echo CHECK-'{name}'-ok; "
                    f"else echo CHECK-'{name}'-failed; fi")
            time.sleep(0.5)
        markers = [f"CHECK-{n}-".encode() for n in checks]
        error = vm.wait_for(lambda s: all(m in s for m in markers), CHECK_TIMEOUT)
        failed = [n for n in checks if f"CHECK-{n}-ok".encode() not in vm.seen]
        if error:
            return f"{error} while running checks", False
        if failed:
            return f"checks failed: {', '.join(failed)}", False
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


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("mode", choices=["live", "encrypted", "rejected"])
    parser.add_argument("args", nargs="+")
    parser.add_argument("--secure-boot", metavar="VARS")
    parser.add_argument("--timeout", type=int, default=900)
    opts = parser.parse_args()
    if opts.mode == "live":
        message, ok = test_live(*opts.args, opts.timeout, opts.secure_boot)
    elif opts.mode == "encrypted":
        message, ok = test_encrypted(*opts.args, opts.timeout)
    else:
        if not opts.secure_boot:
            parser.error("rejected needs --secure-boot")
        message, ok = test_rejected(*opts.args, opts.timeout, opts.secure_boot)
    print(f"\n==> Boot test ({opts.mode}): {message}", flush=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
