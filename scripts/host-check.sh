#!/usr/bin/env bash
# Check that the build host has the tools LFS chapter 2 requires.
. "$(dirname "$0")/lib.sh"

missing=()
for tool in bash ld bison bzip2 chown diff find gawk gcc g++ grep gzip m4 \
            make patch perl python3 sed tar makeinfo xz; do
  command -v "$tool" >/dev/null || missing+=("$tool")
done
[ "${#missing[@]}" -eq 0 ] || die "missing host tools: ${missing[*]}"

[ "$(readlink -f /bin/sh)" != "/usr/bin/dash" ] && [ "$(readlink -f /bin/sh)" != "/bin/dash" ] \
  || die "/bin/sh must be bash, not dash"

echo 'int main(){}' > /tmp/swissman-dummy.c
g++ -x c++ /tmp/swissman-dummy.c -o /tmp/swissman-dummy || die "host g++ cannot compile"
rm -f /tmp/swissman-dummy.c /tmp/swissman-dummy
log "Host OK: $(gcc --version | head -n1), $(nproc) cores"
