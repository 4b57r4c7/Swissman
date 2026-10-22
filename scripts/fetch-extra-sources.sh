#!/usr/bin/env bash
# Download the sources listed in config/extra-sources.txt (packages that
# are not part of the LFS book) and verify their pinned checksums.
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

while read -r url sum; do
  [[ -n "$url" && "$url" != \#* ]] || continue
  file="$(basename "$url")"
  if ! { [ -f "$file" ] && check "$file" "$sum" 2>/dev/null; }; then
    log "Downloading $file"
    curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  check "$file" "$sum" || die "checksum mismatch for $file"
done < "$REPO_ROOT/config/extra-sources.txt"
log "Extra sources verified"
