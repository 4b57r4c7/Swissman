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
# The book names patches either with or without the package version.
# Prints nothing for an optional patch (third argument "optional").
src_patch() {
  local p
  for p in "$SOURCES/$1-$(src_version "$1")-$2.patch" "$SOURCES/$1-$2.patch"; do
    [ -f "$p" ] && { printf '%s\n' "$p"; return; }
  done
  [ "${3:-}" = optional ] || die "missing patch $1 $2"
}

# Print the single source file matching a glob, e.g. `src_glob 'tcl*-src.tar.gz'`.
src_glob() {
  local matches
  mapfile -t matches < <(compgen -G "$SOURCES/$1" || true)
  [ "${#matches[@]}" -eq 1 ] || die "expected one file for '$1', found ${#matches[@]}"
  printf '%s\n' "${matches[0]}"
}

# Extract a package into a fresh work directory and cd into it. The
# optional second argument is a glob for packages whose tarball name does
# not follow <name>-<version>. The caller runs in a subshell, so the cd
# does not leak.
enter_src() {
  local name="$1" tarball dir
  if [ -n "${2:-}" ]; then
    tarball="$(src_glob "$2")"
  else
    tarball="$(src_tarball "$name")"
  fi
  mkdir -p "$WORK"
  # Use the tarball's own top-level directory; it does not always match
  # the file name (e.g. tcl8.6.18-src.tar.gz unpacks to tcl8.6.18).
  dir="$(tar -tf "$tarball" | awk -F/ '{ sub(/^\.\//, "") } $1 != "" && !d { print $1; d = 1 }')"
  [ -n "$dir" ] || die "cannot determine top-level directory of $tarball"
  rm -rf "${WORK:?}/$dir"
  tar -xf "$tarball" -C "$WORK"
  cd "$WORK/$dir"
}

# Run a build step in a subshell and clean up its work directory afterwards.
build_step() {
  local script="$1"
  log "Building $(basename "$script" .sh)"
  ( . "$script" )
  rm -rf "$WORK"
}
