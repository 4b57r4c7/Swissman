#!/usr/bin/env bash
# Run a directory of build steps inside a chroot of $LFS (LFS chapter 7).
# Must run as root. The repo and sources are copied to /swissman inside
# the chroot and removed again afterwards.
. "$(dirname "$0")/lib.sh"

steps="${1:?usage: chroot-build.sh <steps-dir relative to repo>}"
[ "$(id -u)" -eq 0 ] || die "chroot-build.sh must run as root"

# LFS chapter 7.2: the system's files belong to root, not the build user.
chown -R root:root "$LFS"/{usr,var,etc}
[ -d "$LFS/tools" ] && chown -R root:root "$LFS/tools"
chown -R root:root "$LFS/lib64"

cleanup() {
  mountpoint -q "$LFS/dev/shm" && umount "$LFS/dev/shm"
  for m in dev/pts sys proc run dev; do
    mountpoint -q "$LFS/$m" && umount "$LFS/$m"
  done
  rm -rf "$LFS/swissman"
}
trap cleanup EXIT

# LFS chapter 7.3: virtual kernel file systems.
mkdir -pv "$LFS"/{dev,proc,sys,run}
mount -v --bind /dev "$LFS/dev"
mount -vt devpts devpts -o gid=5,mode=0620 "$LFS/dev/pts"
mount -vt proc proc "$LFS/proc"
mount -vt sysfs sysfs "$LFS/sys"
mount -vt tmpfs tmpfs "$LFS/run"
if [ -h "$LFS/dev/shm" ]; then
  install -v -d -m 1777 "$LFS$(realpath /dev/shm)"
else
  mount -vt tmpfs -o nosuid,nodev tmpfs "$LFS/dev/shm"
fi

log "Copying build scripts and sources into the chroot"
mkdir -p "$LFS/swissman"
cp -a "$REPO_ROOT"/{config,scripts} "$LFS/swissman/"
cp -a "$SOURCES" "$LFS/swissman/$SOURCES_DIR"

# LFS chapter 7.4: enter the chroot with a clean environment.
chroot "$LFS" /usr/bin/env -i \
  HOME=/root \
  TERM=dumb \
  PATH=/usr/bin:/usr/sbin \
  MAKEFLAGS="-j$JOBS" \
  TESTSUITEFLAGS="-j$JOBS" \
  JOBS="$JOBS" \
  /bin/bash /swissman/scripts/run-steps.sh "/swissman/$steps"
