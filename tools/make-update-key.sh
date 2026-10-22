#!/usr/bin/env bash
# Generate the Ed25519 key pair that signs releases.
#
# Usage: make-update-key.sh <private-key.pem>
# Writes the private key (keep it secret, off GitHub unless you choose to
# store it as a repository secret) and the public key into
# config/update-signing.pem, which every image built afterwards trusts.
# Needs openssl.
set -euo pipefail

key="${1:?usage: make-update-key.sh <private-key.pem>}"
[ -e "$key" ] && { echo "$key exists; not overwriting" >&2; exit 1; }
( umask 077; openssl genpkey -algorithm ed25519 -out "$key" )
openssl pkey -in "$key" -pubout -out "$(dirname "$0")/../config/update-signing.pem"
echo "Private key: $key. Public key: config/update-signing.pem (commit it)." >&2
