#!/usr/bin/env bash
set -euo pipefail

case ${1:-} in
--help|-h)
  printf 'Usage: helix-recovery-receipt {restic|hamology}\n'
  exit 0
  ;;
restic|hamology)
  [[ $# -eq 1 ]] || exit 2
  ;;
*)
  printf 'Usage: helix-recovery-receipt {restic|hamology}\n' >&2
  exit 2
  ;;
esac

directory=/var/lib/helix/recovery
if [[ ${HELIX_RECOVERY_TEST_MODE:-0} == 1 ]]; then
  directory=${HELIX_RECOVERY_TEST_ROOT:-}
  [[ $directory == /tmp/* && -d $directory ]] || exit 1
elif ((EUID != 0)); then
  printf 'Recovery receipt writer requires root\n' >&2
  exit 1
fi

# ExecStartPost invokes this only after a backup program succeeds.
# Persist locally so reboots and a missing NAS do not erase the evidence.
umask 077
install -d -m 0755 -- "$directory"
[[ ! -L $directory ]] || exit 1
record=$directory/last-success-$1
tmp=$(mktemp "$directory/.last-success-$1.XXXXXXXX")
trap 'rm -f -- "$tmp"' EXIT
printf '%s\n' "$(date -u +%s)" > "$tmp"
chmod 0644 "$tmp"
mv -Tf -- "$tmp" "$record"
trap - EXIT
