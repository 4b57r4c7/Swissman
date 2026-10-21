# LFS chapter 7.11: mpdecimal, needed by Python's decimal module.
enter_src mpdecimal
./configure --prefix=/usr \
            --disable-static \
            --docdir="/usr/share/doc/mpdecimal-$(src_version mpdecimal)"
make -j"$JOBS"
make install
