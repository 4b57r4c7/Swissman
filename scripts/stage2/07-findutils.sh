# LFS chapter 6.8: Findutils.
enter_src findutils
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(build-aux/config.guess)" \
            --localstatedir=/var/lib/locate
make -j"$JOBS"
make DESTDIR="$LFS" install
