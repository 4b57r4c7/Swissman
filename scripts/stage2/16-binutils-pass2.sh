# LFS chapter 6.17: Binutils, second pass, built to run on the target.
enter_src binutils
# Keep libtool from linking against the host's libraries.
sed '6031s/$add_dir//' -i ltmain.sh
mkdir -v build && cd build
../configure --prefix=/usr \
             --build="$(../config.guess)" \
             --host="$SWISSMAN_TGT" \
             --disable-nls \
             --enable-shared \
             --enable-gprofng=no \
             --disable-werror \
             --enable-64-bit-bfd \
             --enable-new-dtags \
             --enable-default-hash-style=gnu
make -j"$JOBS"
make DESTDIR="$LFS" install
rm -v "$LFS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
