# LFS chapter 6.12: Make.
enter_src make
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(build-aux/config.guess)"
make -j"$JOBS"
make DESTDIR="$LFS" install
