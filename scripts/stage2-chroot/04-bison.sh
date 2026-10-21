# LFS chapter 7.8: Bison.
enter_src bison
./configure --prefix=/usr \
            --docdir="/usr/share/doc/bison-$(src_version bison)"
make -j"$JOBS"
make install
