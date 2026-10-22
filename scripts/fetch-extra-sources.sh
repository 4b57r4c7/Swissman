#!/usr/bin/env bash
# Download the sources listed in config/extra-sources.txt (packages that
# are not part of the LFS book) and verify their pinned checksums. A
# source without a release tarball is cloned from git at a tag, checked
# against its pinned commit and packed into <name>-<version>.tar.gz.
. "$(dirname "$0")/lib.sh"

mkdir -p "$SOURCES"
cd "$SOURCES"

check() {
  case "${#2}" in
    64) echo "$2  $1" | sha256sum -c --quiet - ;;
    128) echo "$2  $1" | sha512sum -c --quiet - ;;
    *) die "unsupported checksum for $1" ;;
  esac
}

fetch_git() {
  local url="${1#git+}" tag="${1##*@}" commit="$2" name dir
  url="${url%@*}"
  name="$(basename "$url" .git)-${tag#v}"
  [ -f "$name.tar.gz" ] && [ "$(cat "$name.commit" 2>/dev/null)" = "$commit" ] && return
  log "Cloning $name"
  dir="$(mktemp -d)"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "$url" "$dir/$name"
  [ "$(git -C "$dir/$name" rev-parse HEAD)" = "$commit" ] || die "$url $tag is not commit $commit"
  rm -rf "$dir/$name/.git"
  tar -czf "$name.tar.gz" -C "$dir" "$name"
  echo "$commit" > "$name.commit"
  rm -rf "$dir"
}

while read -r url sum; do
  [[ -n "$url" && "$url" != \#* ]] || continue
  if [[ "$url" = git+* ]]; then
    fetch_git "$url" "$sum"
    continue
  fi
  file="$(basename "$url")"
  if ! { [ -f "$file" ] && check "$file" "$sum" 2>/dev/null; }; then
    log "Downloading $file"
    curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  check "$file" "$sum" || die "checksum mismatch for $file"
done < "$REPO_ROOT/config/extra-sources.txt"
log "Extra sources verified"
