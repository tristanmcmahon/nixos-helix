#!/usr/bin/env bash

set -euo pipefail

[[ $# -eq 1 ]] || { printf 'Usage: %s BACKUP_ROOT\n' "${0##*/}" >&2; exit 2; }
backup_root=$(readlink -f "$1")
[[ -d $backup_root ]]
temporary_manifest=$(mktemp)
trap 'rm -f -- "$temporary_manifest"' EXIT
(
  cd "$backup_root"
  find . -type f ! -path './SHA256SUMS' -print0 |
    sort -z |
    xargs -0 -r sha256sum
) >"$temporary_manifest"
(
  cd "$backup_root"
  sha256sum --check "$temporary_manifest"
)
install -m 0444 "$temporary_manifest" "$backup_root/.SHA256SUMS.new"
mv -f "$backup_root/.SHA256SUMS.new" "$backup_root/SHA256SUMS"
printf 'Installed verified manifest: %s/SHA256SUMS\n' "$backup_root"
