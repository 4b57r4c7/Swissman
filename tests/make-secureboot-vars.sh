#!/usr/bin/env bash
# Make an OVMF variable store with Secure Boot enabled and only our own
# keys enrolled (no Microsoft keys), as on a machine set up for Swissman.
#
# Usage: make-secureboot-vars.sh <certs-dir> <output.fd>
# <certs-dir> holds PK.crt, KEK.crt and db.crt (see sign-kernel.sh).
# Needs virt-fw-vars (python3-virt-firmware) and OVMF.
set -euo pipefail

certs="$1" output="$2"
owner="$(cat /proc/sys/kernel/random/uuid)"
virt-fw-vars --input /usr/share/OVMF/OVMF_VARS_4M.fd --output "$output" \
  --set-pk "$owner" "$certs/PK.crt" \
  --add-kek "$owner" "$certs/KEK.crt" \
  --add-db "$owner" "$certs/db.crt" \
  --secure-boot
