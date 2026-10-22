# nftables and the netfilter libraries it needs (BLFS, "Networking
# Libraries" and "Security"). Not part of the LFS book; the sources come
# from config/extra-sources.txt.
(
  enter_src libmnl
  ./configure --prefix=/usr --disable-static
  make
  make install
)
(
  enter_src libnftnl
  ./configure --prefix=/usr --disable-static
  make
  make install
)
enter_src nftables
./configure --prefix=/usr --sysconfdir=/etc --disable-static --disable-debug \
  --disable-man-doc --with-cli=readline --without-json --without-unitdir
make
make install
