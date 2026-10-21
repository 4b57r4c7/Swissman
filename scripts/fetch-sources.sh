#!/usr/bin/env bash
# Download every source tarball and patch listed by the pinned LFS release
# and verify it against the checksums published with that release.
. "$(dirname "$0")/lib.sh"

BOOK_URL="https://www.linuxfromscratch.org/lfs/view/$LFS_VERSION"
mkdir -p "$SOURCES"
cd "$SOURCES"

log "Fetching package list for LFS $LFS_VERSION"
curl -fsSL --retry 5 -o wget-list "$BOOK_URL/wget-list-sysv"
curl -fsSL --retry 5 -o md5sums "$BOOK_URL/md5sums"

failed=()
while read -r url; do
  [ -n "$url" ] || continue
  file="$(basename "$url")"
  if [ -f "$file" ] && grep -q " $file\$" md5sums && \
     grep " $file\$" md5sums | md5sum -c --quiet - 2>/dev/null; then
    continue
  fi
  log "Downloading $file"
  if ! curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o "$file.part" "$url"; then
    failed+=("$url")
    continue
  fi
  mv "$file.part" "$file"
done < wget-list

[ "${#failed[@]}" -eq 0 ] || die "failed to download: ${failed[*]}"

log "Verifying checksums"
md5sum -c --quiet md5sums

# MD5 only proves we got what the LFS book lists. Record SHA-256 too so a
# later step can pin and verify sources with a stronger hash.
sha256sum $(awk '{print $2}' md5sums) > SHA256SUMS
log "All $(wc -l < md5sums) sources verified"
