#!/usr/bin/env bash
# Assemble the live ISO from $LFS: the root file system as a squashfs image
# and the kernel (with its built-in initramfs) as the EFI boot loader.
# Runs on the build host as root; needs squashfs-tools, xorriso, mtools
# and dosfstools.
. "$(dirname "$0")/lib.sh"

[ "$(id -u)" -eq 0 ] || die "make-iso.sh must run as root"
kernel="$LFS/boot/vmlinuz.efi"
[ -f "$kernel" ] || die "kernel not found at $kernel"

iso_tree="$WORK/iso"
out="$REPO_ROOT/out"
rm -rf "$iso_tree"
mkdir -p "$iso_tree/live" "$out"

log "Compressing the root file system"
mksquashfs "$LFS" "$iso_tree/live/rootfs.sfs" -noappend -comp zstd -Xcompression-level 19 \
  -wildcards -e 'proc/*' 'sys/*' 'dev/*' 'run/*' 'tmp/*'

log "Creating the EFI system partition image"
esp="$WORK/efiboot.img"
size_kib=$(( ($(stat -c %s "$kernel") / 1024) + 4096 ))
rm -f "$esp"
truncate -s "${size_kib}K" "$esp"
mkfs.vfat -n SWISSEFI "$esp"
mmd -i "$esp" ::/EFI ::/EFI/BOOT
mcopy -i "$esp" "$kernel" ::/EFI/BOOT/BOOTX64.EFI

log "Writing the ISO"
iso="$out/swissman.iso"
xorriso -as mkisofs \
  -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
  -volid SWISSMAN \
  -partition_offset 16 \
  -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "$esp" \
  -appended_part_as_gpt \
  -e --interval:appended_partition_2:all:: -no-emul-boot \
  -output "$iso" "$iso_tree"
( cd "$out" && sha256sum swissman.iso > swissman.iso.sha256 )
rm -rf "$iso_tree" "$esp"
log "Wrote $(du -h "$iso" | cut -f1) to out/swissman.iso"
