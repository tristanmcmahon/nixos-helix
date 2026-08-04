#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

printf '%s\n' \
  'HELIX REINSTALL PREFLIGHT — READ ONLY' \
  'No disk is considered safe to erase by this script.' \
  'Partitioning and formatting require a separate manual gate.'

printf '\nRepository\n'
printf 'Path:   %s\n' "$repo_root"
printf 'Branch: %s\n' "$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '(detached)')"
printf 'Commit: %s\n' "$(git -C "$repo_root" rev-parse HEAD)"
if [[ -n $(git -C "$repo_root" status --short) ]]; then
  printf 'State:  dirty; preserve this patch with the backup\n'
  git -C "$repo_root" status --short
else
  printf 'State:  clean\n'
fi

printf '\nStorage and boot inventory\n'
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL
findmnt --real
bootctl status || true
printf '\nTracked hardware configuration checksum\n'
sha256sum "$repo_root/hardware-configuration.nix"

printf '\nRuntime-data readiness (contents are never printed)\n'
authorized_keys=/home/tristan/.ssh/authorized_keys
if [[ -s $authorized_keys ]] && grep -Eq '^[[:space:]]*[^#[:space:]]' "$authorized_keys"; then
  printf 'SSH authorized keys: present\n'
else
  printf 'SSH authorized keys: MISSING\n'
fi
credential=/etc/nixos/secrets/infernalnexus-smb
if sudo -n test -f "$credential" 2>/dev/null; then
  printf 'NAS credential: present; metadata '
  sudo -n stat -c '%U:%G %a' "$credential"
else
  printf 'NAS credential: absent or metadata requires an interactive root check\n'
fi

printf '\nNetwork\n'
ip -brief link
ip -brief address
ip route
if ping -c 1 -W 2 channels.nixos.org >/dev/null 2>&1; then
  printf 'channels.nixos.org: reachable\n'
else
  printf 'channels.nixos.org: not confirmed reachable\n'
fi

printf '\nRequired independent backup scope\n'
printf '%s\n' \
  '/home/tristan' \
  '/home/tristan/Projects' \
  '/home/tristan/.ssh' \
  '/etc/nixos/secrets' \
  "$repo_root/hardware-configuration.nix" \
  'repository commit and any uncommitted patch' \
  'browser bookmarks/profiles that are not synchronised elsewhere' \
  'Obsidian vaults and all other non-reproducible local data'
printf '\nRecord a backup destination on a physically separate device and follow docs/reinstall.md.\n'
