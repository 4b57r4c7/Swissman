# LFS chapter 6.15: Tar.
enter_src tar
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(build-aux/config.guess)"
make -j"$JOBS"
make DESTDIR="$LFS" install
