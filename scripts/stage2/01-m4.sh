# LFS chapter 6.2: M4.
mkdir -p "$LFS/usr/share"
cat > "$LFS/usr/share/config.site" << "EOF"
ac_cv_func_posix_spawn_file_actions_addchdir=yes
ac_cv_func_posix_spawn_file_actions_addfchdir=yes
EOF
enter_src m4
./configure --prefix=/usr \
            --host="$SWISSMAN_TGT" \
            --build="$(build-aux/config.guess)"
make -j"$JOBS"
make DESTDIR="$LFS" install
