# LFS chapter 6.5: Coreutils.
enter_src coreutils
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(build-aux/config.guess)" \
            --enable-install-program=hostname
make -j"$JOBS"
make DESTDIR="$LFS" install
mv -v "$LFS/usr/bin/chroot" "$LFS/usr/sbin"
mkdir -pv "$LFS/usr/share/man/man8"
mv -v "$LFS/usr/share/man/man1/chroot.1" "$LFS/usr/share/man/man8/chroot.8"
sed -i 's/"1"/"8"/' "$LFS/usr/share/man/man8/chroot.8"
