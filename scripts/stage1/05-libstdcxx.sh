# LFS chapter 5.6: libstdc++ for the cross toolchain.
enter_src gcc
mkdir -v build && cd build
../libstdc++-v3/configure --host="$SWISSMAN_TGT" \
                          --build="$(../config.guess)" \
                          --prefix=/usr \
                          --disable-multilib \
                          --disable-nls \
                          --disable-libstdcxx-pch \
                          --with-gxx-include-dir="/tools/$SWISSMAN_TGT/include/c++/$(src_version gcc)"
make -j"$JOBS"
make DESTDIR="$LFS" install
rm -fv "$LFS"/usr/lib/lib{stdc++{,exp,fs},supc++}.la
