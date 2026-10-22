#!/usr/bin/env bash
# Build a disk image that looks like an installed Swissman system: one GPT
# partition encrypted with LUKS2, holding an ext4 file system with the root
# file system from the ISO. Prints the LUKS UUID to pass as swissman.root.
#
# Usage: sudo make-encrypted-disk.sh <iso> <image> <passphrase>
# Needs cryptsetup, e2fsprogs, sfdisk, squashfs-tools, util-linux and xorriso.
set -euo pipefail

iso="$1" image="$2" passphrase="$3"
[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }

work="$(mktemp -d)"
loop=
cleanup() {
  mountpoint -q "$work/mnt" && umount "$work/mnt"
  [ -e /dev/mapper/swissman-test ] && cryptsetup close swissman-test
  [ -n "$loop" ] && losetup -d "$loop"
  rm -rf "$work"
}
trap cleanup EXIT

xorriso -osirrox on -indev "$iso" -extract /live/rootfs.sfs "$work/rootfs.sfs" >&2

rm -f "$image"
truncate -s 4G "$image"
echo 'label: gpt
name=swissman-root' | sfdisk -q "$image"
# Attach just the partition, so this works without partition scanning.
read -r start size < <(sfdisk -d "$image" | sed -n 's/.*start= *\([0-9]*\), size= *\([0-9]*\).*/\1 \2/p')
part="$(losetup --show -f --offset $((start * 512)) --sizelimit $((size * 512)) "$image")"
loop="$part"

# Weak key derivation settings keep the test fast; the passphrase still
# goes through Argon2id.
printf '%s' "$passphrase" | cryptsetup luksFormat -q --type luks2 \
  --pbkdf argon2id --pbkdf-force-iterations 4 --pbkdf-memory 65536 --key-file - "$part"
printf '%s' "$passphrase" | cryptsetup open --key-file - "$part" swissman-test
mkfs.ext4 -q -L swissman-root /dev/mapper/swissman-test
mkdir "$work/mnt"
mount /dev/mapper/swissman-test "$work/mnt"
unsquashfs -q -f -d "$work/mnt" "$work/rootfs.sfs" >&2
umount "$work/mnt"

cryptsetup luksUUID "$part"
