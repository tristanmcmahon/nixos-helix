#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 ]]; then
  printf 'Usage: %s HARDWARE_FILE HARDWARE_FILE [...]\n' "${0##*/}" >&2
  exit 2
fi
reference=$1
shift
[[ -s $reference ]]
for hardware_file in "$@"; do
  cmp -s -- "$reference" "$hardware_file" || {
    printf 'Hardware configuration mismatch: %s differs from %s\n' \
      "$hardware_file" "$reference" >&2
    exit 1
  }
done
printf 'Hardware configurations are byte-identical: %s\n' "$(sha256sum "$reference" | cut -d' ' -f1)"
