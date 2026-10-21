# LFS chapter 6.18: GCC, second pass, built to run on the target.
enter_src gcc
for dep in mpfr gmp mpc; do
  tar -xf "$(src_tarball "$dep")"
  mv -v "$dep-$(src_version "$dep")" "$dep"
done
sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64

mkdir -v build && cd build
../configure --build="$(../config.guess)" \
             --host="$SWISSMAN_TGT" \
             --target="$SWISSMAN_TGT" \
             --prefix=/usr \
             --with-build-sysroot="$LFS" \
             --enable-default-pie \
             --enable-default-ssp \
             --disable-fixincludes \
             --disable-nls \
             --disable-multilib \
             --disable-libatomic \
             --disable-libgomp \
             --disable-libquadmath \
             --disable-libsanitizer \
             --disable-libssp \
             --disable-libvtv \
             --enable-languages=c,c++ \
             CXX_FOR_TARGET="$SWISSMAN_TGT-gcc -nostdinc++" \
             LDFLAGS_FOR_TARGET="-L$PWD/$SWISSMAN_TGT/libgcc" \
             target_configargs=gcc_cv_target_thread_file=posix
make -j"$JOBS"
make DESTDIR="$LFS" install
ln -sv gcc "$LFS/usr/bin/cc"
