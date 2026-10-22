# Contents of the initramfs that is built into the kernel. With
# swissman.root=<blkid tag> on the kernel command line it boots an
# installed system: it unlocks the root partition if it is LUKS encrypted,
# with a FIDO2 security key when one is enrolled, and mounts it. Without it, it boots the live system: it finds the boot
# medium by its label and mounts the compressed root file system with a
# writable layer in RAM on top. Either way it then hands over to systemd.
dst=/usr/src/initramfs
rm -rf "$dst"
mkdir -pv "$dst"/{bin,dev,proc,sys,run,media,lower,rw,newroot,usr/lib,lib64}
ln -sv usr/lib "$dst/lib"

copy_libs() {
  local lib
  for lib in $(ldd "$1" | grep -o '/[^ ]*'); do
    cp -L "$lib" "$dst/usr/lib/"
  done
}
for bin in bash mount umount switch_root blkid mkdir sleep cryptsetup \
    /usr/lib/systemd/systemd-cryptsetup; do
  bin="$(command -v "$bin")"
  install -m755 "$bin" "$dst/bin/"
  copy_libs "$bin"
done
# systemd-cryptsetup loads these at run time, so ldd does not list them.
for lib in libcryptsetup.so.12 libfido2.so.1; do
  cp -L "/usr/lib/$lib" "$dst/usr/lib/"
  copy_libs "/usr/lib/$lib"
done
# glibc loads libgcc_s at run time to unwind threads.
cp -L "$(gcc -print-file-name=libgcc_s.so.1)" "$dst/usr/lib/"
ln -sfv ../lib/ld-linux-x86-64.so.2 "$dst/lib64/ld-linux-x86-64.so.2"

cat > "$dst/init" << "EOF2"
#!/bin/bash
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
# Handed over to systemd at the end; cryptsetup keeps its locks here.
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run

rescue() {
  echo "swissman initramfs: $*; starting a rescue shell" > /dev/console
  exec bash < /dev/console > /dev/console 2>&1
}

# Print the device matching a blkid tag such as UUID=..., waiting for it
# to appear.
find_device() {
  local dev
  for _ in {1..30}; do
    dev="$(blkid -l -o device -t "$1")" && [ -n "$dev" ] && { echo "$dev"; return; }
    sleep 1
  done
  return 1
}

# The live system logs root in on the console without a password; the
# root account itself stays locked. systemd keeps /run from the initramfs
# and reads these drop-ins from it, so an installed system never has them.
getty_dropin() {
  mkdir -p "/run/systemd/system/$1.d"
  printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -o %s --autologin root %s - $TERM\n' \
    "'-p -f -- \\\\u'" "$2" > "/run/systemd/system/$1.d/live-autologin.conf"
}

boot_live() {
  local dev m
  dev="$(find_device LABEL=SWISSMAN)" || rescue "boot medium with label SWISSMAN not found"
  mount -o ro "$dev" /media || rescue "cannot mount $dev"
  mount -o ro,loop -t squashfs /media/live/rootfs.sfs /lower || rescue "cannot mount the root image"
  mount -t tmpfs -o mode=0755 tmpfs /rw
  mkdir -p /rw/upper /rw/work
  mount -t overlay overlay -o lowerdir=/lower,upperdir=/rw/upper,workdir=/rw/work /newroot \
    || rescue "cannot set up the overlay"

  mkdir -p /run/live/{medium,lower,rw}
  for m in media:medium lower:lower rw:rw; do
    mount -n --move "/${m%%:*}" "/run/live/${m#*:}"
  done

  getty_dropin getty@tty1.service --noclear
  getty_dropin serial-getty@ttyS0.service "--keep-baud 115200,57600,38400,9600"
}

# Wait a few seconds for a FIDO2 security key: a hidraw device whose
# report descriptor declares the FIDO usage page (0xF1D0).
wait_for_security_key() {
  local d
  for _ in {1..20}; do
    for d in /sys/class/hidraw/*/device/report_descriptor; do
      [ -e "$d" ] && [[ "$(< "$d")" == *$'\x06\xd0\xf1'* ]] 2>/dev/null && return
    done
    sleep 0.5
  done
}

boot_installed() {
  local dev d
  dev="$(find_device "$1")" || rescue "root device $1 not found"
  if cryptsetup isLuks "$dev"; then
    if [[ "$(cryptsetup luksDump "$dev")" == *systemd-fido2* ]]; then
      # Unlocks with the security key, asking for its PIN and a touch or
      # fingerprint as enrolled; without the key it asks for the passphrase.
      echo "Unlocking $dev: insert your security key, or wait to type the passphrase." \
        > /dev/console
      wait_for_security_key
      systemd-cryptsetup attach root "$dev" - fido2-device=auto,token-timeout=15s,tries=3 \
        || rescue "cannot unlock $dev"
    else
      # cryptsetup asks for the passphrase on the console, up to three times.
      cryptsetup open --type luks2 "$dev" root || rescue "cannot unlock $dev"
    fi
    # Without udev there is no /dev/mapper/root link; find the dm device.
    for d in /sys/block/dm-*; do
      [ "$(< "$d/dm/name")" = root ] && dev="/dev/${d##*/}"
    done
  fi
  mount -o rw "$dev" /newroot || rescue "cannot mount $dev"
}

root=
read -r -a args < /proc/cmdline
for arg in "${args[@]}"; do
  case "$arg" in
    swissman.root=*) root="${arg#swissman.root=}" ;;
  esac
done
if [ -n "$root" ]; then
  boot_installed "$root"
else
  boot_live
fi

mount -n --move /run /newroot/run
exec switch_root /newroot /usr/lib/systemd/systemd
EOF2
chmod 755 "$dst/init"

# Device nodes cannot live in a plain directory, so list them separately.
cat > /usr/src/initramfs.list << "EOF2"
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
EOF2
