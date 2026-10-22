# Contents of the initramfs that is built into the kernel. It finds the
# boot medium by its label, mounts the compressed root file system with a
# writable layer in RAM on top, and hands over to systemd.
dst=/usr/src/initramfs
rm -rf "$dst"
mkdir -pv "$dst"/{bin,dev,proc,sys,media,lower,rw,newroot,usr/lib,lib64}
ln -sv usr/lib "$dst/lib"

copy_with_libs() {
  local bin="$1" lib
  install -m755 "$(command -v "$bin")" "$dst/bin/"
  for lib in $(ldd "$(command -v "$bin")" | grep -o '/[^ ]*'); do
    cp -L "$lib" "$dst/usr/lib/"
  done
}
for bin in bash mount umount switch_root blkid mkdir sleep; do
  copy_with_libs "$bin"
done
ln -sfv ../lib/ld-linux-x86-64.so.2 "$dst/lib64/ld-linux-x86-64.so.2"

cat > "$dst/init" << "EOF2"
#!/bin/bash
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

rescue() {
  echo "swissman initramfs: $*; starting a rescue shell" > /dev/console
  exec bash < /dev/console > /dev/console 2>&1
}

dev=
for _ in {1..30}; do
  dev="$(blkid -l -o device -t LABEL=SWISSMAN)" && [ -n "$dev" ] && break
  sleep 1
done
[ -n "$dev" ] || rescue "boot medium with label SWISSMAN not found"

mount -o ro "$dev" /media || rescue "cannot mount $dev"
mount -o ro,loop -t squashfs /media/live/rootfs.sfs /lower || rescue "cannot mount the root image"
mount -t tmpfs -o mode=0755 tmpfs /rw
mkdir -p /rw/upper /rw/work
mount -t overlay overlay -o lowerdir=/lower,upperdir=/rw/upper,workdir=/rw/work /newroot \
  || rescue "cannot set up the overlay"

mkdir -p /newroot/run/live
mount -t tmpfs tmpfs /newroot/run
mkdir -p /newroot/run/live/{medium,lower,rw}
for m in media:medium lower:lower rw:rw; do
  mount -n --move "/${m%%:*}" "/newroot/run/live/${m#*:}"
done

# The live system logs root in on the console without a password; the
# root account itself stays locked. systemd keeps /run from the initramfs
# and reads these drop-ins from it, so an installed system never has them.
getty_dropin() {
  mkdir -p "/newroot/run/systemd/system/$1.d"
  printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -o %s --autologin root %s - $TERM\n' \
    "'-p -f -- \\\\u'" "$2" > "/newroot/run/systemd/system/$1.d/live-autologin.conf"
}
getty_dropin getty@tty1.service --noclear
getty_dropin serial-getty@ttyS0.service "--keep-baud 115200,57600,38400,9600"

exec switch_root /newroot /usr/lib/systemd/systemd
EOF2
chmod 755 "$dst/init"

# Device nodes cannot live in a plain directory, so list them separately.
cat > /usr/src/initramfs.list << "EOF2"
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
EOF2
