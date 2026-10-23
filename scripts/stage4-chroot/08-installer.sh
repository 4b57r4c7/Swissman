# The installer and the updater (system/), with what they need beyond the
# rest of the system: dosfstools to format the EFI system partition and
# the Mozilla CA certificates, so the updater can check the certificate of
# the download server. The sources come from config/extra-sources.txt.
(
  enter_src dosfstools
  ./configure --prefix=/usr --enable-compat-symlinks --mandir=/usr/share/man \
    --docdir=/usr/share/doc/dosfstools
  make
  make install
)
# The certifi package carries Mozilla's CA list as one PEM file, which is
# where OpenSSL (built with --openssldir=/etc/ssl) looks by default.
(
  enter_src certifi
  install -v -m644 certifi/cacert.pem /etc/ssl/cert.pem
)

cp -rv --preserve=mode "$REPO_ROOT/system/." /
# Set the modes here too: the ISO cache key hashes file contents, not modes.
chmod -v 755 /usr/bin/swissman-install /usr/bin/swissman-update /usr/lib/swissman/*
install -v -m755 "$REPO_ROOT/tools/make-secureboot-keys.sh" /usr/lib/swissman/

# Releases are signed with this key (see docs/updates.md). Without it, the
# updater trusts only keys the owner puts in /etc/swissman/update-keys.
mkdir -pv /usr/share/swissman/update-keys
if [ -f "$REPO_ROOT/config/update-signing.pem" ]; then
  install -v -m644 "$REPO_ROOT/config/update-signing.pem" /usr/share/swissman/update-keys/release.pem
fi
