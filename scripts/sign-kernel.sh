#!/usr/bin/env bash
# Sign the kernel in $LFS/boot for UEFI Secure Boot, as the boot loader of
# the live ISO. The signed copy goes to out/swissman.efi; the kernel in the
# system stays unsigned, because the installer signs it with the
# computer's own keys. Runs on the build host as root; needs sbsigntool
# and openssl.
#
# Release builds sign with the db key from the SECUREBOOT_DB_KEY
# environment variable (a PEM private key, from a repository secret) and
# the matching public certificates in config/secureboot/. Without that
# variable, it creates throwaway test keys, so the Secure Boot tests still
# run; such an image only boots with Secure Boot on a machine that trusts
# those test keys, which nothing does outside the test.
#
# The public certificates in use, and whether they are release or test
# keys, are written to out/secureboot/ for the tests and the ISO.
. "$(dirname "$0")/lib.sh"

[ "$(id -u)" -eq 0 ] || die "sign-kernel.sh must run as root"
kernel="$(readlink -f "$LFS/boot/vmlinuz.efi")"
[ -f "$kernel" ] || die "kernel not found at $LFS/boot/vmlinuz.efi"

keys="$(mktemp -d)"
trap 'rm -rf "$keys"' EXIT
certs="$REPO_ROOT/out/secureboot"
rm -rf "$certs"
mkdir -p "$certs"

if [ -n "${SECUREBOOT_DB_KEY:-}" ]; then
  log "Signing with the release db key"
  ( umask 077; printf '%s\n' "$SECUREBOOT_DB_KEY" > "$keys/db.key" )
  cp "$REPO_ROOT"/config/secureboot/{PK,KEK,db}.crt "$certs/"
  # Refuse a key that does not belong to the published db certificate.
  [ "$(openssl pkey -in "$keys/db.key" -pubout)" = "$(openssl x509 -in "$certs/db.crt" -noout -pubkey)" ] \
    || die "SECUREBOOT_DB_KEY does not match config/secureboot/db.crt"
  echo release > "$certs/MODE"
else
  log "No release key; signing with throwaway test keys"
  "$REPO_ROOT/tools/make-secureboot-keys.sh" "$keys" "Swissman TEST ONLY"
  cp "$keys"/{PK,KEK,db}.crt "$certs/"
  echo test > "$certs/MODE"
fi
cp "$certs/db.crt" "$keys/db.crt"

signed="$REPO_ROOT/out/swissman.efi"
sbsign --key "$keys/db.key" --cert "$keys/db.crt" --output "$signed" "$kernel"
sbverify --cert "$keys/db.crt" "$signed"
log "Signed $(basename "$kernel") ($(cat "$certs/MODE") keys) as out/swissman.efi"
