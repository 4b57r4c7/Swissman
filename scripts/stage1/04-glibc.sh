# LFS chapter 5.5: glibc, cross-compiled into $LFS.
ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"

enter_src glibc
patch -Np1 -i "$(src_patch glibc fhs-1)"
upstream_fixes="$(src_patch glibc upstream_fixes-1 optional)"
[ -z "$upstream_fixes" ] || patch -Np1 -i "$upstream_fixes"
mkdir -v build && cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure --prefix=/usr \
             --host="$SWISSMAN_TGT" \
             --build="$(../scripts/config.guess)" \
             --disable-nscd \
             libc_cv_slibdir=/usr/lib \
             --enable-kernel="$GLIBC_MIN_KERNEL"
make -j"$JOBS"
make DESTDIR="$LFS" install
sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"

# Sanity check: the cross compiler must link against the new glibc.
echo 'int main(){}' | "$SWISSMAN_TGT-gcc" -x c - -o a.out
"$SWISSMAN_TGT-readelf" -l a.out | grep -q '\[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2\]' \
  || die "cross toolchain sanity check failed"
log "Sanity check passed"
