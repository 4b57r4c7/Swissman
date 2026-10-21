#!/usr/bin/env python3
"""Boot the ISO in QEMU with UEFI firmware and wait for a login prompt.

Usage: qemu-boot.py <iso> [timeout-seconds]

The serial console is copied to stdout and to out/boot.log. Exits 0 when
"login:" appears, 1 on a kernel panic, an initramfs rescue shell or a
timeout.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import time

OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS = "/usr/share/OVMF/OVMF_VARS_4M.fd"
SUCCESS = b"login:"
FAILURES = [b"Kernel panic", b"rescue shell", b"Failed to start Switch Root"]


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
    proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    os.set_blocking(proc.stdout.fileno(), False)
    seen = b""
    deadline = time.time() + timeout
    result = None
    while result is None:
        if time.time() > deadline:
            result = ("timeout", 1)
            break
        chunk = proc.stdout.read()
        if chunk:
            sys.stdout.buffer.write(chunk)
            sys.stdout.flush()
            log.write(chunk)
            seen = (seen + chunk)[-4096:]
            if SUCCESS in seen:
                result = ("reached the login prompt", 0)
            for f in FAILURES:
                if f in seen:
                    result = (f"saw '{f.decode()}'", 1)
        elif proc.poll() is not None:
            result = (f"QEMU exited with {proc.returncode}", 1)
        else:
            time.sleep(0.2)
    proc.kill()
    print(f"\n==> Boot test: {result[0]}", flush=True)
    sys.exit(result[1])


if __name__ == "__main__":
    main()
