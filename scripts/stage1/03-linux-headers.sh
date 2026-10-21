# LFS chapter 5.4: sanitized kernel API headers for glibc.
enter_src linux
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include "$LFS/usr"
