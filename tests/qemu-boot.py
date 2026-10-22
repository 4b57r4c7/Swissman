#!/usr/bin/env python3
"""Boot Swissman in QEMU with UEFI firmware and check the running system.

Usage:
  qemu-boot.py live <iso> [timeout-seconds]
  qemu-boot.py encrypted <kernel> <disk> <luks-uuid> <passphrase> [timeout-seconds]

live: boots the ISO, waits for the live system to log root in on the
serial console, then runs the checks in CHECKS there.

encrypted: boots the kernel on its own against a disk made by
make-encrypted-disk.sh, the way an installed system boots. It first
enters a wrong passphrase, which must be refused, then the right one,
and waits for the login prompt of the system on the encrypted disk.

The serial console is copied to stdout and to out/boot-<mode>.log. Exits 0
on success, 1 on a kernel panic, an initramfs rescue shell, a failed check
or a timeout.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.fd"
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


class Machine:
    def __init__(self, args, log_path):
        vars_copy = tempfile.NamedTemporaryFile(suffix=".fd", delete=False).name
        shutil.copy(OVMF_VARS, vars_copy)
        cmd = ["qemu-system-x86_64", "-machine", "q35", "-m", "2048", "-smp", "2",
               "-nographic", "-no-reboot",
               "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
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


def test_live(iso, timeout):
    vm = Machine(["-cdrom", iso], "out/boot-live.log")
    try:
        error = vm.expect(b"(automatic login)", timeout)
        if error:
            return f"{error} before the automatic login", False
        time.sleep(3)  # let the shell start
        vm.forget()
        for name, check in CHECKS.items():
            vm.send(f"if {check}; then echo CHECK-'{name}'-ok; "
                    f"else echo CHECK-'{name}'-failed; fi")
            time.sleep(0.5)
        markers = [f"CHECK-{n}-".encode() for n in CHECKS]
        error = vm.wait_for(lambda s: all(m in s for m in markers), CHECK_TIMEOUT)
        failed = [n for n in CHECKS if f"CHECK-{n}-ok".encode() not in vm.seen]
        if error:
            return f"{error} while running checks", False
        if failed:
            return f"checks failed: {', '.join(failed)}", False
        return f"all checks passed: {', '.join(CHECKS)}", True
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


def main():
    mode, args = sys.argv[1], sys.argv[2:]
    if mode == "live":
        timeout = int(args[1]) if len(args) > 1 else 900
        message, ok = test_live(args[0], timeout)
    elif mode == "encrypted":
        timeout = int(args[4]) if len(args) > 4 else 900
        message, ok = test_encrypted(*args[:4], timeout)
    else:
        sys.exit(__doc__)
    print(f"\n==> Boot test ({mode}): {message}", flush=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
