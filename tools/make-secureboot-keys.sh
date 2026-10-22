#!/usr/bin/env bash
# Generate your own Secure Boot keys: the platform key (PK), the key
# exchange key (KEK) and the signature database key (db).
#
# Usage: make-secureboot-keys.sh <output-dir> [owner-name]
#
# Writes <name>.key (private, keep secret) and <name>.crt (public) for each
# key, plus <name>.cer, the same certificate in the DER format that firmware
# setup screens import. Only db.key is needed to sign kernels; keep PK.key
# and KEK.key offline. Needs openssl.
set -euo pipefail

out="${1:?usage: make-secureboot-keys.sh <output-dir> [owner-name]}"
owner="${2:-Swissman}"
umask 077
mkdir -p "$out"
for name in PK KEK db; do
  [ -e "$out/$name.key" ] && { echo "$out/$name.key exists; not overwriting" >&2; exit 1; }
  openssl req -new -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -subj "/CN=$owner $name/" -keyout "$out/$name.key" -out "$out/$name.crt"
  openssl x509 -in "$out/$name.crt" -outform DER -out "$out/$name.cer"
  chmod 644 "$out/$name.crt" "$out/$name.cer"
done
echo "Keys written to $out. Keep the .key files secret." >&2
