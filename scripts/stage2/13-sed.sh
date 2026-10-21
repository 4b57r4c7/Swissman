# LFS chapter 6.14: Sed.
enter_src sed
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(./build-aux/config.guess)"
make -j"$JOBS"
make DESTDIR="$LFS" install
