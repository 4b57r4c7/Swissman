# LFS chapter 7.7: only the three Gettext programs other packages need.
enter_src gettext
./configure --disable-shared
make -j"$JOBS"
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
