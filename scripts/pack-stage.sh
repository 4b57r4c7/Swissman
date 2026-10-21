#!/usr/bin/env bash
# Pack the current contents of $LFS into out/<name>.tar.zst so the next
# CI job can pick up where this one stopped.
. "$(dirname "$0")/lib.sh"

name="${1:?usage: pack-stage.sh <name>}"
mkdir -p "$REPO_ROOT/out"
tar --numeric-owner -C "$LFS" -cf - . | zstd -T0 -10 -o "$REPO_ROOT/out/$name.tar.zst"
( cd "$REPO_ROOT/out" && sha256sum "$name.tar.zst" > "$name.tar.zst.sha256" )
log "Packed $(du -h "$REPO_ROOT/out/$name.tar.zst" | cut -f1) into out/$name.tar.zst"
