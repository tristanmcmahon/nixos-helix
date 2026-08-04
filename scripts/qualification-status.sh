#!/usr/bin/env bash

set -euo pipefail

printf '%s\n' 'HELIX QUALIFICATION STATUS — READ ONLY'
printf 'Cleanup timer enabled: %s\n' "$(systemctl is-enabled helix-nix-cleanup.timer 2>&1 || true)"
printf 'Cleanup timer active:  %s\n' "$(systemctl is-active helix-nix-cleanup.timer 2>&1 || true)"

running=$(readlink -f /run/current-system)
persistent=$(readlink -f /nix/var/nix/profiles/system)
printf 'Running system:    %s\n' "$running"
printf 'Persistent system: %s\n' "$persistent"

printf '\nAvailable system generations\n'
shopt -s nullglob
generation_links=(/nix/var/nix/profiles/system-*-link)
if ((${#generation_links[@]} == 0)); then
  printf '(none visible)\n'
fi
for generation_link in "${generation_links[@]}"; do
  generation_path=$(readlink -f "$generation_link")
  markers=()
  [[ $generation_path == "$running" ]] && markers+=(running)
  [[ $generation_path == "$persistent" ]] && markers+=(persistent)
  printf '%s -> %s' "${generation_link##*/}" "$generation_path"
  if ((${#markers[@]})); then
    printf ' [%s]' "${markers[*]}"
  fi
  printf '\n'
done
