#!/usr/bin/env bash
# Prepare the files of a release from a built ISO: the ISO itself, its
# root file system image (swissman-rootfs.sfs, which swissman-update
# installs), MANIFEST, which names the version and the image's checksum,
# and SHA256SUMS. The manifest still needs signing with sign-release.sh.
#
# Usage: make-release.sh <iso> <version> <output-dir>
# Needs xorriso.
set -euo pipefail

iso="$1" version="$2" out="$3"
[[ "$version" =~ ^[0-9A-Za-z.+~-]+$ ]] || { echo "invalid version: $version" >&2; exit 1; }
mkdir -p "$out"
cp "$iso" "$out/swissman.iso"
xorriso -osirrox on -indev "$iso" -extract /live/rootfs.sfs "$out/swissman-rootfs.sfs" 2> /dev/null
chmod 644 "$out/swissman-rootfs.sfs"
cd "$out"
{
  echo "swissman-release 1"
  echo "version $version"
  echo "sha256 $(sha256sum swissman-rootfs.sfs | cut -d' ' -f1) swissman-rootfs.sfs"
} > MANIFEST
sha256sum swissman.iso swissman-rootfs.sfs > SHA256SUMS
echo "Release $version prepared in $out; sign MANIFEST with sign-release.sh" >&2
