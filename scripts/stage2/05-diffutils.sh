# LFS chapter 6.6: Diffutils.
enter_src diffutils
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(./build-aux/config.guess)" \
            gl_cv_func_strcasecmp_works=yes
make -j"$JOBS"
make DESTDIR="$LFS" install
