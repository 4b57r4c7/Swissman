#!/usr/bin/env bash
# Download every source tarball and patch listed by the pinned LFS book and
# verify it against the checksums published with that book. The kernel is
# replaced by the pinned LTS release and verified by its GPG signature.
. "$(dirname "$0")/lib.sh"

BOOK_URL="https://www.linuxfromscratch.org/lfs/view/$LFS_BOOK"
mkdir -p "$SOURCES"
cd "$SOURCES"

log "Fetching package list for LFS $LFS_BOOK"
curl -fsSL --retry 5 -o wget-list.book "$BOOK_URL/$LFS_WGET_LIST"
curl -fsSL --retry 5 -o md5sums.book "$BOOK_URL/md5sums"

# Drop the book's kernel; we fetch our own below.
grep -Ev '/linux-[0-9][^/]*\.tar\.xz$' wget-list.book > wget-list
grep -Ev ' linux-[0-9][^ ]*\.tar\.xz$' md5sums.book > md5sums

download() {
  curl -fL --retry 5 --retry-delay 5 --connect-timeout 30 -o "$2.part" "$1" && mv "$2.part" "$2"
}

failed=()
while read -r url; do
  [ -n "$url" ] || continue
  file="$(basename "$url")"
  if [ -f "$file" ] && grep " $file\$" md5sums | md5sum -c --quiet - 2>/dev/null; then
    continue
  fi
  log "Downloading $file"
  download "$url" "$file" || failed+=("$url")
done < wget-list

[ "${#failed[@]}" -eq 0 ] || die "failed to download: ${failed[*]}"

log "Verifying checksums"
md5sum -c --quiet md5sums

kernel="linux-$KERNEL_VERSION"
[ -f "$kernel.tar.xz" ] || download "$KERNEL_URL/$kernel.tar.xz" "$kernel.tar.xz"
download "$KERNEL_URL/$kernel.tar.sign" "$kernel.tar.sign"

log "Verifying the $kernel signature"
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
for signer in $KERNEL_SIGNERS; do
  email="${signer%%:*}" fpr="${signer#*:}"
  gpg --batch --quiet --auto-key-locate clear,wkd --locate-keys "$email" >/dev/null
  # WKD is fetched over TLS, but only keep a key whose fingerprint we pinned.
  gpg --batch --list-keys --with-colons "$email" | grep -q "^fpr:::::::::$fpr:" \
    || die "key for $email does not match pinned fingerprint $fpr"
  gpg --batch --export "$fpr" >> "$GNUPGHOME/trusted.gpg"
done
xz -dc "$kernel.tar.xz" | gpgv --keyring "$GNUPGHOME/trusted.gpg" "$kernel.tar.sign" - \
  || die "bad signature on $kernel.tar.xz"
rm -rf "$GNUPGHOME"

# MD5 only proves we got what the LFS book lists. Record SHA-256 too so a
# later step can pin and verify sources with a stronger hash.
sha256sum $(awk '{print $2}' md5sums) "$kernel.tar.xz" > SHA256SUMS
log "All $(wc -l < SHA256SUMS) sources verified"
