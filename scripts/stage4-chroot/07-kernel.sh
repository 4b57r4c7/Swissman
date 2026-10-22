# Build the hardened LTS kernel with the initramfs built in, so the
# kernel image alone is a bootable EFI application (LFS chapter 10).
enter_src linux
make mrproper

scripts/kconfig/merge_config.sh -m arch/x86/configs/x86_64_defconfig \
  "$REPO_ROOT/config/kernel/swissman.config"
scripts/config --set-str INITRAMFS_SOURCE "/usr/src/initramfs /usr/src/initramfs.list"
scripts/config --set-val INITRAMFS_ROOT_UID 0 --set-val INITRAMFS_ROOT_GID 0
make olddefconfig

# Report every requested option that did not stick, and stop if a
# required one is missing.
grep -E '^(CONFIG_|# CONFIG_)' "$REPO_ROOT/config/kernel/swissman.config" | while read -r line; do
  grep -qxF "$line" .config || echo "note: kernel option not applied: $line"
done
missing=0
while read -r line; do
  [[ "$line" = CONFIG_* ]] || continue
  grep -qxF "$line" .config || { echo "required kernel option missing: $line"; missing=1; }
done < "$REPO_ROOT/config/kernel/required.txt"
[ "$missing" -eq 0 ] || die "kernel configuration is missing required options"

make -j"$JOBS"
make INSTALL_MOD_STRIP=1 modules_install

kver="$(make -s kernelrelease)"
install -v -m644 arch/x86/boot/bzImage "/boot/vmlinuz-$kver.efi"
install -v -m644 .config "/boot/config-$kver"
ln -sfv "vmlinuz-$kver.efi" /boot/vmlinuz.efi
# The installer and swissman-update build the signed boot image from the
# kernel that belongs to the /usr they install, so it lives next to its
# modules.
install -v -m644 arch/x86/boot/bzImage "/usr/lib/modules/$kver/vmlinuz"
