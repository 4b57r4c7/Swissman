# LFS chapter 6.4: Bash.
enter_src bash
./configure --prefix=/usr \
            --build="$(sh support/config.guess)" \
            --host="$SWISSMAN_TGT" \
            --without-bash-malloc \
            --docdir="/usr/share/doc/bash-$(src_version bash)"
make -j"$JOBS"
make DESTDIR="$LFS" install
ln -sv bash "$LFS/bin/sh"
