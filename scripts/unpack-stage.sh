#!/usr/bin/env bash
# Restore $LFS from out/<name>.tar.zst after checking its SHA-256 sum.
. "$(dirname "$0")/lib.sh"

name="${1:?usage: unpack-stage.sh <name>}"
( cd "$REPO_ROOT/out" && sha256sum -c "$name.tar.zst.sha256" )
mkdir -p "$LFS"
zstd -dc "$REPO_ROOT/out/$name.tar.zst" | tar -xpf - --numeric-owner -C "$LFS"
log "Restored $name into $LFS"
