# cryptsetup for LUKS2 disk encryption, with the libraries it needs (BLFS
# "General Libraries" and "File Systems and Disk Management"). Only the
# device-mapper part of LVM2 is built. The sources come from
# config/extra-sources.txt.

# json-c builds with CMake, which LFS does not have; it uses its bundled
# libraries.
(
  enter_src cmake
  sed -i '/"lib64"/s/64//' Modules/GNUInstallDirs.cmake
  ./bootstrap --prefix=/usr --no-system-libs --parallel="$JOBS" \
    --mandir=/share/man --docdir=/share/doc/cmake -- -DCMAKE_BUILD_TYPE=Release
  make
  make install
)
# json-c 0.18 still declares support for CMake older than 3.5, which
# CMake 4 refuses without the policy minimum.
(
  enter_src json-c
  mkdir build
  cd build
  cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_INSTALL_LIBDIR=lib \
    -D CMAKE_BUILD_TYPE=Release -D BUILD_STATIC_LIBS=OFF -D BUILD_TESTING=OFF \
    -D DISABLE_EXTRA_LIBS=ON -D CMAKE_POLICY_VERSION_MINIMUM=3.5 ..
  make
  make install
)
(
  enter_src popt
  ./configure --prefix=/usr --disable-static
  make
  make install
)
(
  enter_src lvm2 'LVM2.*.tgz'
  ./configure --prefix=/usr --enable-pkgconfig --enable-udev_sync \
    --enable-udev_rules --with-udevdir=/usr/lib/udev/rules.d
  make device-mapper
  # The install target relinks dmsetup and races with itself in parallel.
  make -j1 install_device-mapper
)
enter_src cryptsetup
./configure --prefix=/usr --disable-static --disable-asciidoc --disable-ssh-token
make
make install
