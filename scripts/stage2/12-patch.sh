# LFS chapter 6.13: Patch.
enter_src patch
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(build-aux/config.guess)"
make -j"$JOBS"
make DESTDIR="$LFS" install
