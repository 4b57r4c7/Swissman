#!/usr/bin/env bash
# Regenerate the chapter 8 build steps from the LFS book sources for the
# book pinned in config/build.conf. Review the diff before committing.
. "$(dirname "$0")/../scripts/lib.sh"

tag="r${LFS_BOOK%-systemd}"
book="$(mktemp -d)"
trap 'rm -rf "$book"' EXIT

git clone --quiet --depth 1 --branch "$tag" https://github.com/lfs-book/lfs "$book"
( cd "$book" && ./git-version.sh systemd >/dev/null 2>&1 )

out="$REPO_ROOT/scripts/stage3-chroot"
rm -f "$out"/[0-9]*.sh
python3 "$REPO_ROOT/tools/lfs-extract.py" "$book" chapter08 "$out" "LFS $LFS_BOOK"
