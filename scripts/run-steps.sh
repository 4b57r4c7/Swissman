#!/usr/bin/env bash
# Run every numbered build step in a directory, in order.
. "$(dirname "$0")/lib.sh"

dir="${1:?usage: run-steps.sh <steps-dir>}"
for step in "$dir"/[0-9]*.sh; do
  build_step "$step"
done
