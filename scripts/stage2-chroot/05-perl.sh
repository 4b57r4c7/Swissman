# LFS chapter 7.9: Perl.
enter_src perl
v="$(src_version perl)"
v="${v%.*}"
sh Configure -des \
             -D prefix=/usr \
             -D vendorprefix=/usr \
             -D useshrplib \
             -D privlib="/usr/lib/perl5/$v/core_perl" \
             -D archlib="/usr/lib/perl5/$v/core_perl" \
             -D sitelib="/usr/lib/perl5/$v/site_perl" \
             -D sitearch="/usr/lib/perl5/$v/site_perl" \
             -D vendorlib="/usr/lib/perl5/$v/vendor_perl" \
             -D vendorarch="/usr/lib/perl5/$v/vendor_perl"
make -j"$JOBS"
make install
