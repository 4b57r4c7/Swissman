# LFS chapter 7.15: drop documentation, libtool archives and the cross toolchain.
rm -rf /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name \*.la -delete
rm -rf /tools
