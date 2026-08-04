#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-qualification-lib.sh"
# shellcheck disable=SC2154 # Assigned by release-qualification-lib.sh.
qualification_hold=${qualification_hold:?}
# shellcheck disable=SC2154 # Assigned by release-qualification-lib.sh.
qualification_gcroot=${qualification_gcroot:?}
printf '%s\n' 'HELIX QUALIFICATION STATUS — READ ONLY'
if [[ $(qualification_hold_status "$qualification_hold") == active ]]; then
  printf 'Qualification hold: active (%s)\n' "$qualification_hold"
else
  printf 'Qualification hold: inactive (%s absent)\n' "$qualification_hold"
fi
printf 'Cleanup timer enabled: %s\n' "$(systemctl is-enabled helix-nix-cleanup.timer 2>&1 || true)"
printf 'Cleanup timer active:  %s\n' "$(systemctl is-active helix-nix-cleanup.timer 2>&1 || true)"

running=$(readlink -f /run/current-system)
persistent=$(readlink -f /nix/var/nix/profiles/system)
rollback=$(readlink -f "$qualification_gcroot" 2>/dev/null || printf '(absent)')
candidate=$(cat "$qualification_hold/candidate-system-path" 2>/dev/null || printf '(absent)')
printf 'Rollback GC root:  %s\n' "$qualification_gcroot"
printf 'Rollback closure:  %s\n' "$rollback"
printf 'Running system:    %s\n' "$running"
printf 'Persistent system: %s\n' "$persistent"
printf 'Candidate system:  %s\n' "$candidate"

printf '\nAvailable system generations\n'
shopt -s nullglob
generation_links=(/nix/var/nix/profiles/system-*-link)
mapfile -t generation_links < <(printf '%s\n' "${generation_links[@]}" | sort -t- -k2,2n)
if ((${#generation_links[@]} == 0)); then printf '(none visible)\n'; fi
for generation_link in "${generation_links[@]}"; do
  generation_path=$(readlink -f "$generation_link")
  markers=()
  [[ $generation_path == "$running" ]] && markers+=(running)
  [[ $generation_path == "$persistent" ]] && markers+=(persistent)
  [[ $generation_path == "$rollback" ]] && markers+=(rollback)
  printf '%s -> %s' "${generation_link##*/}" "$generation_path"
  ((${#markers[@]})) && printf ' [%s]' "${markers[*]}"
  printf '\n'
done

printf '\nSystemd-boot entries\n'
if boot_entries=$(sudo -n find /boot/loader/entries -maxdepth 1 -type f \
  -name '*.conf' -print 2>/dev/null); then
  if [[ -n $boot_entries ]]; then
    sort <<<"$boot_entries"
  else
    printf '(none present)\n'
  fi
else
  printf '(root access required to inspect /boot/loader/entries)\n'
fi
