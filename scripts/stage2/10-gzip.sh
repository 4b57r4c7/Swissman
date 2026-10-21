# LFS chapter 6.11: Gzip.
enter_src gzip
./configure --prefix=/usr --host="$SWISSMAN_TGT"
make -j"$JOBS"
make DESTDIR="$LFS" install
