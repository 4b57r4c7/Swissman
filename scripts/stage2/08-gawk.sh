# LFS chapter 6.9: Gawk.
enter_src gawk
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(build-aux/config.guess)"
make -j"$JOBS"
make DESTDIR="$LFS" install
