# LFS chapter 6.3: Ncurses.
enter_src ncurses
# Build "tic" for the host first; the cross build needs it.
mkdir build
pushd build
  ../configure --prefix="$LFS/tools" AWK=gawk
  make -C include
  make -C progs tic
  install progs/tic "$LFS/tools/bin"
popd

./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(./config.guess)" \
            --mandir=/usr/share/man \
            --with-manpage-format=normal \
            --with-shared \
            --without-normal \
            --with-cxx-shared \
            --without-debug \
            --without-ada \
            --disable-stripping \
            AWK=gawk
make -j"$JOBS"
make DESTDIR="$LFS" install
ln -sv libncursesw.so "$LFS/usr/lib/libncurses.so"
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"
