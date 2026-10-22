#!/usr/bin/env bash
# Sign the MANIFEST of a release (see make-release.sh) with the release
# key, writing MANIFEST.sig, and check the signature against the public
# key. swissman-update installs a release only with a valid signature.
#
# Usage: sign-release.sh <release-dir> <private-key.pem> [public-key.pem]
# The public key defaults to config/update-signing.pem. Needs openssl 3.
set -euo pipefail

dir="$1" key="$2"
pub="${3:-$(dirname "$0")/../config/update-signing.pem}"
openssl pkeyutl -sign -inkey "$key" -rawin -in "$dir/MANIFEST" -out "$dir/MANIFEST.sig"
openssl pkeyutl -verify -pubin -inkey "$pub" -rawin -in "$dir/MANIFEST" -sigfile "$dir/MANIFEST.sig"
