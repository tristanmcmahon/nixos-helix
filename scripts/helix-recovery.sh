#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: helix-recovery --check\n'
  printf 'Read-only local audit of backup receipts and systemd timers; no NAS access.\n'
}
case ${1:-} in
--help|-h)
  usage
  exit 0
  ;;
--check)
  [[ $# -eq 1 ]] || { usage >&2; exit 2; }
  ;;
*)
  usage >&2
  exit 2
  ;;
esac

directory=/var/lib/helix/recovery
if [[ ${HELIX_RECOVERY_TEST_MODE:-0} == 1 ]]; then
  directory=${HELIX_RECOVERY_TEST_ROOT:-}
  [[ $directory == /tmp/* && -d $directory ]] || exit 2
fi
now=$(date -u +%s)
max_age=172800
failed=0

check_unit() {
  local name=$1 timer=$2 file=$directory/last-success-$1
  local epoch age
  if ! systemctl is-active --quiet "$timer"; then
    printf 'FAIL %-9s timer inactive: %s\n' "$name" "$timer"
    failed=1
  fi
  if [[ ! -f $file || -L $file ]]; then
    printf 'FAIL %-9s no successful backup receipt\n' "$name"
    failed=1
    return
  fi
  if [[ ${HELIX_RECOVERY_TEST_MODE:-0} != 1 && $(stat -c '%u:%a' "$file") != "0:644" ]]; then
    printf 'FAIL %-9s receipt not root-owned mode 0644\n' "$name"
    failed=1
    return
  fi
  epoch=$(<"$file")
  if [[ ! $epoch =~ ^[0-9]{10,}$ ]]; then
    printf 'FAIL %-9s malformed backup receipt\n' "$name"
    failed=1
    return
  fi
  age=$((now - epoch))
  if ((age < -300)); then
    printf 'FAIL %-9s receipt lies in the future\n' "$name"
    failed=1
  elif ((age > max_age)); then
    printf 'FAIL %-9s last successful run %sh ago (max 48h)\n' "$name" "$((age / 3600))"
    failed=1
  else
    printf 'PASS %-9s last successful run %sh ago\n' "$name" "$((age / 3600))"
  fi
}

check_unit restic restic-backups-helix.timer
check_unit hamology hamology-backup.timer
printf '%s\n' 'Note: successful program completion is not an independent restore test.'
if ((failed)); then
  printf 'Helix recovery readiness: FAIL\n'
  exit 1
fi
printf 'Helix recovery readiness: PASS\n'
