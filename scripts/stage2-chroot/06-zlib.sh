# LFS chapter 7.10: Zlib.
enter_src zlib
./configure --prefix=/usr
make -j"$JOBS"
make install
rm -fv /usr/lib/libz.a
