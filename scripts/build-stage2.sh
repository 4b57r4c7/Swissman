#!/usr/bin/env bash
# Stage 2, part 1: cross-compile the temporary tools into $LFS
# (LFS chapter 6). Runs as an unprivileged user on top of stage 1.
. "$(dirname "$0")/lib.sh"

[ -x "$LFS/tools/bin/$SWISSMAN_TGT-gcc" ] || die "stage 1 toolchain not found in $LFS"

# Same clean environment as stage 1 (LFS chapter 4.4).
export LC_ALL=POSIX
export PATH="$LFS/tools/bin:/usr/bin:/bin"
export CONFIG_SITE="$LFS/usr/share/config.site"
export LFS SWISSMAN_TGT
umask 022

"$REPO_ROOT/scripts/run-steps.sh" "$REPO_ROOT/scripts/stage2"
log "Temporary tools cross-compiled"
