# LFS chapter 6.16: Xz.
enter_src xz
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(build-aux/config.guess)" \
            --disable-static \
            --docdir="/usr/share/doc/xz-$(src_version xz)"
make -j"$JOBS"
make DESTDIR="$LFS" install
rm -v "$LFS/usr/lib/liblzma.la"
