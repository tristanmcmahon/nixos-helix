#!/usr/bin/env bash

set -euo pipefail

mount_path=/mnt/infernalnexus/nas1
max_mib=1024
max_seconds=600

if [[ ${1:-} == --run && $# -eq 1 ]]; then
  printf 'Opt-in NAS read test: at most %s MiB and %s seconds; no writes.\n' \
    "$max_mib" "$max_seconds"
  timeout "$max_seconds" "$0" --execute
  findmnt "$mount_path"
  journalctl -u mnt-infernalnexus-nas1.automount \
    -u mnt-infernalnexus-nas1.mount --since '-15 minutes' --no-pager
  exit 0
elif [[ ${1:-} != --execute || $# -ne 1 ]]; then
  printf 'Usage: %s --run\n' "${0##*/}" >&2
  exit 2
fi

read_mib=0
files=0
while IFS= read -r -d '' file; do
  ((read_mib >= max_mib)) && break
  size=$(stat -c %s "$file") || exit 1
  file_mib=$(((size + 1048575) / 1048576))
  ((file_mib > 64)) && file_mib=64
  remaining=$((max_mib - read_mib))
  ((file_mib > remaining)) && file_mib=$remaining
  ((file_mib == 0)) && continue
  printf 'Reading file %d: %d MiB (total cap %d MiB)\n' \
    "$((files + 1))" "$file_mib" "$max_mib"
  dd if="$file" of=/dev/null bs=1M count="$file_mib" status=progress
  read_mib=$((read_mib + file_mib))
  files=$((files + 1))
done < <(find "$mount_path" -xdev -type f -readable -print0)
printf 'Read test completed: %d files, at most %d MiB requested.\n' "$files" "$read_mib"
