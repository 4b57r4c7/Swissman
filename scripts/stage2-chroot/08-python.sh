# LFS chapter 7.12: Python.
enter_src Python
./configure --prefix=/usr \
            --enable-shared \
            --without-ensurepip \
            --without-static-libpython
make -j"$JOBS"
make install
