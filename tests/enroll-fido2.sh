#!/usr/bin/env bash
# Enroll a FIDO2 security key into the LUKS2 header of a disk image made
# by make-encrypted-disk.sh, next to its passphrase, the way a user would
# with systemd-cryptenroll. The key needs no PIN (like virtual-fido2.py).
#
# Usage: sudo enroll-fido2.sh <image> <passphrase> <hidraw device>
# Needs systemd-cryptenroll with libfido2, sfdisk and util-linux.
set -euo pipefail

image="$1" passphrase="$2" hidraw="$3"
[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }

read -r start size < <(sfdisk -d "$image" | sed -n 's/.*start= *\([0-9]*\), size= *\([0-9]*\).*/\1 \2/p')
part="$(losetup --show -f --offset $((start * 512)) --sizelimit $((size * 512)) "$image")"
trap 'losetup -d "$part"' EXIT

PASSWORD="$passphrase" systemd-cryptenroll --fido2-device="$hidraw" \
  --fido2-with-client-pin=no --fido2-with-user-presence=yes "$part"
cryptsetup luksDump "$part" | grep -q systemd-fido2
