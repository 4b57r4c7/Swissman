# FIDO2 security keys for unlocking encrypted disks: libcbor and libfido2
# (BLFS) with its fido2-token tool, then systemd again with cryptsetup and
# FIDO2 support, which the LFS build leaves out. That adds
# systemd-cryptenroll, to enroll a key into a LUKS2 header, and
# systemd-cryptsetup, which the initramfs uses to unlock with it. systemd
# loads libcryptsetup and libfido2 at run time.
#
# The same build adds what the installer needs for the boot image:
# systemd-stub and ukify, to combine the kernel and its command line into
# one unified kernel image (UKI), and systemd-sbsign to sign it. Building
# the stub needs pyelftools; ukify needs pefile.
# The sources come from config/extra-sources.txt.
(
  enter_src libcbor
  mkdir build
  cd build
  cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_INSTALL_LIBDIR=lib \
    -D CMAKE_BUILD_TYPE=Release -D BUILD_SHARED_LIBS=ON -D WITH_EXAMPLES=OFF ..
  make
  make install
)
(
  enter_src libfido2
  # Warnings from newer compilers must not fail the build.
  sed -i '/add_compile_options(-Werror)/d' CMakeLists.txt
  mkdir build
  cd build
  cmake -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_INSTALL_LIBDIR=lib \
    -D CMAKE_BUILD_TYPE=Release -D BUILD_STATIC_LIBS=OFF -D BUILD_EXAMPLES=OFF \
    -D BUILD_MANPAGES=OFF -D BUILD_TESTS=OFF ..
  make
  make install
)
for pkg in pyelftools pefile; do
  (
    enter_src "$pkg"
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
    pip3 install --no-index --find-links dist "$pkg"
  )
done
# The same options as the LFS build, plus the crypto and boot features.
enter_src systemd
mkdir -p build
cd build
meson setup ..                \
      --prefix=/usr           \
      --buildtype=release     \
      -D default-dnssec=no    \
      -D firstboot=false      \
      -D install-tests=false  \
      -D ldconfig=false       \
      -D sysusers=false       \
      -D rpmmacrosdir=no      \
      -D homed=disabled       \
      -D man=disabled         \
      -D mode=release         \
      -D pamconfdir=no        \
      -D dev-kvm-mode=0660    \
      -D nobody-group=nogroup \
      -D sysupdate=disabled   \
      -D ukify=enabled        \
      -D bootloader=enabled   \
      -D libcryptsetup=enabled \
      -D libcryptsetup-plugins=enabled \
      -D libfido2=enabled     \
      -D docdir=/usr/share/doc/systemd-261.2
ninja
ninja install
test -x /usr/bin/systemd-cryptenroll || die "systemd was built without cryptsetup support"
test -f /usr/lib/systemd/boot/efi/linuxx64.efi.stub || die "systemd was built without systemd-stub"
command -v ukify > /dev/null || die "systemd was built without ukify"
command -v systemd-sbsign > /dev/null || die "systemd was built without systemd-sbsign"
