# LFS chapter 6.10: Grep.
enter_src grep
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(./build-aux/config.guess)"
make -j"$JOBS"
make DESTDIR="$LFS" install
