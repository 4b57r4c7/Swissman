# LFS chapter 5.2: cross binutils.
enter_src binutils
mkdir -v build && cd build
../configure --prefix="$LFS/tools" \
             --with-sysroot="$LFS" \
             --target="$SWISSMAN_TGT" \
             --disable-nls \
             --enable-gprofng=no \
             --disable-werror \
             --enable-new-dtags \
             --enable-default-hash-style=gnu
make -j"$JOBS"
make install
