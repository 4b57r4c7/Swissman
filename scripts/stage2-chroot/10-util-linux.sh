# LFS chapter 7.14: Util-linux.
mkdir -pv /var/lib/hwclock
enter_src util-linux
./configure --libdir=/usr/lib \
            --runstatedir=/run \
            --disable-chfn-chsh \
            --disable-login \
            --disable-nologin \
            --disable-su \
            --disable-setpriv \
            --disable-runuser \
            --disable-pylibmount \
            --disable-static \
            --disable-liblastlog2 \
            --without-python \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir="/usr/share/doc/util-linux-$(src_version util-linux)"
make -j"$JOBS"
make install
