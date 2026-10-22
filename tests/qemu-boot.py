#!/usr/bin/env python3
"""Boot the ISO in QEMU with UEFI firmware and check the running system.

Usage: qemu-boot.py <iso> [timeout-seconds]

Waits for the live system to log root in on the serial console, then runs
the checks in CHECKS there. The serial console is copied to stdout and to
out/boot.log. Exits 0 when every check passes, 1 on a kernel panic, an
initramfs rescue shell, a failed check or a timeout.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS = "/usr/share/OVMF/OVMF_VARS_4M.fd"
LOGGED_IN = b"(automatic login)"
FAILURES = [b"Kernel panic", b"rescue shell", b"Failed to start Switch Root"]
CHECK_TIMEOUT = 120

# Shell commands run on the booted system, by name. A check passes when
# its command succeeds. The marker is quoted so the echoed command line
# itself does not match.
CHECKS = {
    "firewall": "systemctl is-active -q nftables && "
                "nft list chain inet filter input | grep -q 'policy drop'",
    "sysctl": "[ \"$(sysctl -n kernel.kptr_restrict)\" = 2 ] && "
              "[ \"$(sysctl -n kernel.yama.ptrace_scope)\" = 2 ]",
    "lockdown": "grep -q '\\[integrity\\]' /sys/kernel/security/lockdown",
}


def main():
    iso = sys.argv[1]
    timeout = int(sys.argv[2]) if len(sys.argv) > 2 else 900
    vars_copy = tempfile.NamedTemporaryFile(suffix=".fd", delete=False).name
    shutil.copy(OVMF_VARS, vars_copy)

    cmd = ["qemu-system-x86_64", "-machine", "q35", "-m", "2048", "-smp", "2",
           "-nographic", "-no-reboot",
           "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
           "-drive", f"if=pflash,format=raw,file={vars_copy}",
           "-cdrom", iso]
    if os.access("/dev/kvm", os.R_OK | os.W_OK):
        cmd[1:1] = ["-enable-kvm", "-cpu", "host"]
    else:
        print("KVM not available, using emulation (slow)", flush=True)

    os.makedirs("out", exist_ok=True)
    log = open("out/boot.log", "wb")
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    os.set_blocking(proc.stdout.fileno(), False)
    seen = b""

    def wait_for(done, deadline):
        """Copy console output until done(seen) is true; return an error or None."""
        nonlocal seen
        while not done(seen):
            if time.time() > deadline:
                return "timeout"
            chunk = proc.stdout.read()
            if chunk:
                sys.stdout.buffer.write(chunk)
                sys.stdout.flush()
                log.write(chunk)
                seen = (seen + chunk)[-65536:]
                for f in FAILURES:
                    if f in seen:
                        return f"saw '{f.decode()}'"
            elif proc.poll() is not None:
                return f"QEMU exited with {proc.returncode}"
            else:
                time.sleep(0.2)
        return None

    result = None
    error = wait_for(lambda s: LOGGED_IN in s, time.time() + timeout)
    if error:
        result = (f"{error} before the automatic login", 1)
    else:
        time.sleep(3)  # let the shell start
        seen = b""
        for name, check in CHECKS.items():
            line = (f"if {check}; then echo CHECK-'{name}'-ok; "
                    f"else echo CHECK-'{name}'-failed; fi\n")
            proc.stdin.write(line.encode())
            proc.stdin.flush()
            time.sleep(0.5)
        markers = [f"CHECK-{n}-".encode() for n in CHECKS]
        error = wait_for(lambda s: all(m in s for m in markers),
                         time.time() + CHECK_TIMEOUT)
        failed = [n for n in CHECKS if f"CHECK-{n}-ok".encode() not in seen]
        if error:
            result = (f"{error} while running checks", 1)
        elif failed:
            result = (f"checks failed: {', '.join(failed)}", 1)
        else:
            result = (f"all checks passed: {', '.join(CHECKS)}", 0)
    proc.kill()
    print(f"\n==> Boot test: {result[0]}", flush=True)
    sys.exit(result[1])


if __name__ == "__main__":
    main()
