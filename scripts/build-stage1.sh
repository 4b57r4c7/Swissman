#!/usr/bin/env bash
# Stage 1: build the cross toolchain into $LFS/tools (LFS chapters 4-5).
. "$(dirname "$0")/lib.sh"

[ -d "$LFS" ] && [ -w "$LFS" ] || die "$LFS must exist and be writable by $(id -un)"

# A clean environment, as recommended by LFS chapter 4.4.
export LC_ALL=POSIX
export PATH="$LFS/tools/bin:/usr/bin:/bin"
export CONFIG_SITE="$LFS/usr/share/config.site"
export LFS SWISSMAN_TGT
umask 022

log "Creating the $LFS directory layout"
mkdir -pv "$LFS"/{etc,var,tools} "$LFS"/usr/{bin,lib,sbin}
for d in bin lib sbin; do ln -sfnv "usr/$d" "$LFS/$d"; done
mkdir -pv "$LFS/lib64"

for step in "$REPO_ROOT"/scripts/stage1/[0-9]*.sh; do
  build_step "$step"
done

log "Stage 1 complete: $("$SWISSMAN_TGT-gcc" --version | head -n1)"
