#!/usr/bin/env bash
# Shared helpers for Swissman build scripts.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.conf
. "$REPO_ROOT/config/build.conf"

SOURCES="$REPO_ROOT/$SOURCES_DIR"
WORK="${WORK:-$REPO_ROOT/work}"
JOBS="${JOBS:-$(nproc)}"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# Print the path of the single source tarball matching a package name,
# e.g. `src_tarball gcc` -> sources/gcc-15.2.0.tar.xz
src_tarball() {
  local name="$1" matches
  mapfile -t matches < <(find "$SOURCES" -maxdepth 1 -type f \
    -regex ".*/${name}-[0-9][^/]*\.tar\.\(xz\|gz\|bz2\)" | sort)
  [ "${#matches[@]}" -eq 1 ] || die "expected one tarball for '$name', found ${#matches[@]}"
  printf '%s\n' "${matches[0]}"
}

# Version string of a package, derived from its tarball name.
src_version() {
  local base
  base="$(basename "$(src_tarball "$1")")"
  base="${base#"$1"-}"
  printf '%s\n' "${base%.tar.*}"
}

# Path of a patch from the LFS patch set, e.g. `src_patch glibc fhs-1`.
src_patch() {
  local p="$SOURCES/$1-$(src_version "$1")-$2.patch"
  [ -f "$p" ] || die "missing patch $p"
  printf '%s\n' "$p"
}

# Extract a package into a fresh work directory and cd into it.
# The caller runs in a subshell, so the cd does not leak.
enter_src() {
  local name="$1" tarball dir
  tarball="$(src_tarball "$name")"
  mkdir -p "$WORK"
  dir="$WORK/$(basename "${tarball%.tar.*}")"
  rm -rf "$dir"
  tar -xf "$tarball" -C "$WORK"
  cd "$dir"
}

# Run a build step in a subshell and clean up its work directory afterwards.
build_step() {
  local script="$1"
  log "Building $(basename "$script" .sh)"
  ( . "$script" )
  rm -rf "$WORK"
}
