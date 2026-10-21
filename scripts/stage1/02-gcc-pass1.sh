# LFS chapter 5.3: cross GCC without a C library.
enter_src gcc
for dep in mpfr gmp mpc; do
  tar -xf "$(src_tarball "$dep")"
  mv -v "$dep-$(src_version "$dep")" "$dep"
done
# Install 64-bit libraries into "lib" rather than "lib64".
sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64

mkdir -v build && cd build
../configure --target="$SWISSMAN_TGT" \
             --prefix="$LFS/tools" \
             --with-glibc-version="$(src_version glibc)" \
             --with-sysroot="$LFS" \
             --with-newlib \
             --without-headers \
             --enable-default-pie \
             --enable-default-ssp \
             --disable-nls \
             --disable-shared \
             --disable-multilib \
             --disable-threads \
             --disable-libatomic \
             --disable-libgomp \
             --disable-libquadmath \
             --disable-libssp \
             --disable-libvtv \
             --disable-libstdcxx \
             --enable-languages=c,c++
make -j"$JOBS"
make install

# The internal limits.h installed above is incomplete until glibc exists.
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  "$(dirname "$("$SWISSMAN_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"
