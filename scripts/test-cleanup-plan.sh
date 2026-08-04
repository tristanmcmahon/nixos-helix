#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s HELIX_NIX_CLEANUP\n' "${0##*/}" >&2
  exit 2
fi
cleanup=$1
temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT

qualification_hold=$temporary_directory/release-qualification
mkdir "$qualification_hold"
if HELIX_QUALIFICATION_DIR=$qualification_hold \
  "$cleanup" --plan /dev/null 1 >"$temporary_directory/held-output" 2>&1; then
  printf 'FAIL: cleanup planning proceeded during qualification\n' >&2
  exit 1
fi
grep -qF 'Refusing cleanup: release qualification hold exists' \
  "$temporary_directory/held-output"
rmdir "$qualification_hold"
printf 'PASS: qualification hold blocks cleanup planning and execution\n'

assert_plan() {
  local name=$1
  local active=$2
  local retained=$3
  local deleted=$4
  local listing=$5
  local output

  output=$(HELIX_QUALIFICATION_DIR="$temporary_directory/no-qualification-hold" \
    "$cleanup" --plan "$listing" "$active")
  grep -Fx "Active generation: $active" <<<"$output" >/dev/null
  grep -Fx "Retained generations: $retained" <<<"$output" >/dev/null
  grep -Fx "Deleted generations: $deleted" <<<"$output" >/dev/null
  printf 'PASS: %s\n' "$name"
}

write_listing() {
  local destination=$1
  shift
  printf '%s\n' "$@" >"$destination"
}

one="$temporary_directory/one"
write_listing "$one" '  4 2026-08-01 10:00:00 (current)'
assert_plan 'one generation' 4 '4' none "$one"

three="$temporary_directory/three"
write_listing "$three" \
  '  2 2026-07-30 10:00:00' \
  '  7 2026-07-31 10:00:00 (current)' \
  '  9 2026-08-01 10:00:00'
assert_plan 'exactly three generations' 7 '7 9 2' none "$three"

newest_current="$temporary_directory/newest-current"
write_listing "$newest_current" \
  '  1 2026-07-28 10:00:00' \
  '  2 2026-07-29 10:00:00' \
  '  3 2026-07-30 10:00:00' \
  '  4 2026-08-01 10:00:00 (current)'
assert_plan 'newest generation current' 4 '4 3 2' '1' "$newest_current"

rollback="$temporary_directory/rollback"
write_listing "$rollback" \
  '  3 2026-07-28 10:00:00' \
  '  4 2026-07-29 10:00:00 (current)' \
  '  5 2026-07-30 10:00:00' \
  '  6 2026-08-01 10:00:00'
assert_plan 'rollback current is older' 4 '4 6 5' '3' "$rollback"

non_contiguous="$temporary_directory/non-contiguous"
write_listing "$non_contiguous" \
  '  2 2026-07-28 10:00:00' \
  '  8 2026-07-29 10:00:00' \
  ' 21 2026-07-30 10:00:00 (current)' \
  ' 34 2026-08-01 10:00:00'
assert_plan 'non-contiguous generations' 21 '21 34 8' '2' "$non_contiguous"

missing_active="$temporary_directory/missing-active"
write_listing "$missing_active" \
  '  1 2026-07-30 10:00:00' \
  '  2 2026-08-01 10:00:00'
if HELIX_QUALIFICATION_DIR="$temporary_directory/no-qualification-hold" \
  "$cleanup" --plan "$missing_active" 9 >/dev/null 2>&1; then
  printf 'FAIL: missing active generation was accepted\n' >&2
  exit 1
fi
printf 'PASS: missing active generation is rejected\n'

bootloader_rollback="$temporary_directory/bootloader-rollback"
write_listing "$bootloader_rollback" \
  '  7 2026-07-28 10:00:00' \
  ' 10 2026-07-29 10:00:00' \
  ' 11 2026-07-30 10:00:00' \
  ' 12 2026-08-01 10:00:00 (current)'
assert_plan 'bootloader rollback differs from selected profile' 7 '7 12 11' '10' "$bootloader_rollback"
