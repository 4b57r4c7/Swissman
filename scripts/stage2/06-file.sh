# LFS chapter 6.7: File.
enter_src file
# The cross build needs a "file" binary of the same version on the host.
mkdir build
pushd build
  ../configure --disable-bzlib \
               --disable-libseccomp \
               --disable-xzlib \
               --disable-zlib
  make -j"$JOBS"
popd

./configure --prefix=/usr --host="$SWISSMAN_TGT" --build="$(./config.guess)"
make -j"$JOBS" FILE_COMPILE="$(pwd)/build/src/file"
make DESTDIR="$LFS" install
rm -v "$LFS/usr/lib/libmagic.la"
