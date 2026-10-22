#!/usr/bin/env bash
# Download the sources listed in config/extra-sources.txt (packages that
# are not part of the LFS book) and verify their pinned SHA-256 checksums.
. "$(dirname "$0")/lib.sh"

mkdir -p "$SOURCES"
cd "$SOURCES"

while read -r url sum; do
  [[ -n "$url" && "$url" != \#* ]] || continue
  file="$(basename "$url")"
  if ! { [ -f "$file" ] && echo "$sum  $file" | sha256sum -c --quiet - 2>/dev/null; }; then
    log "Downloading $file"
    curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  echo "$sum  $file" | sha256sum -c --quiet - || die "checksum mismatch for $file"
done < "$REPO_ROOT/config/extra-sources.txt"
log "Extra sources verified"
