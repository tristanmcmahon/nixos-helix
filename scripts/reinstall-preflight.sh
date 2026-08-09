#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
root_channel=/nix/var/nix/profiles/per-user/root/channels/nixos
expected_release=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).nixosRelease")
upgrade_state=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).stateVersion")
fresh_state=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).freshStateVersion")
selected_release=$(NIX_PATH="nixpkgs=$root_channel" nix-instantiate --eval --raw -E \
  '(import <nixpkgs> {}).lib.trivial.release' 2>/dev/null || printf unavailable)

printf '%s\n' \
  'HELIX REINSTALL PREFLIGHT — READ ONLY' \
  'No disk is considered safe to erase by this script.' \
  'Partitioning and formatting require a separate manual gate.'

printf '\nRepository and release\n'
printf 'Path:             %s\n' "$repo_root"
printf 'Branch:           %s\n' "$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '(detached)')"
printf 'Commit:           %s\n' "$(git -C "$repo_root" rev-parse HEAD)"
printf 'Origin:           %s\n' "$(git -C "$repo_root" remote get-url origin 2>/dev/null || printf '(missing)')"
printf 'Origin/main:      %s\n' "$(git -C "$repo_root" rev-parse origin/main 2>/dev/null || printf '(missing)')"
printf 'Root channel:     %s\n' "$root_channel"
printf 'Selected release: %s\n' "$selected_release"
printf 'Expected release: %s\n' "$expected_release"
printf 'Upgrade state:    %s\n' "$upgrade_state"
printf 'Fresh state:      %s\n' "$fresh_state"
[[ $repo_root == /home/tristan/Projects/nixos-helix ]] || {
  printf 'FAIL: this is not the canonical Helix checkout.\n' >&2
  exit 1
}
[[ $(git -C "$repo_root" remote get-url origin 2>/dev/null) == \
  https://github.com/tristanmcmahon/nixos-helix.git ]] || {
  printf 'FAIL: origin is not the expected Helix repository.\n' >&2
  exit 1
}
[[ $selected_release == "$expected_release" ]] || {
  printf 'FAIL: the root channel does not select the expected release.\n' >&2
  exit 1
}
if [[ -n $(git -C "$repo_root" status --short) ]]; then
  printf 'State: dirty; preserve this patch with the backup\n'
  git -C "$repo_root" status --short
else
  printf 'State: clean\n'
fi

printf '\nCapacity\n'
for capacity_path in / /nix/store; do
  available_bytes=$(df --output=avail -B1 "$capacity_path" | tail -n 1 | tr -d ' ')
  printf '%s available bytes: %s\n' "$capacity_path" "$available_bytes"
  df -h "$capacity_path" | tail -n 1
  if ((available_bytes < 8 * 1024 * 1024 * 1024)); then
    printf 'FAIL: fewer than 8 GiB are available at %s; do not attempt installation builds.\n' \
      "$capacity_path" >&2
    exit 1
  elif ((available_bytes < 25 * 1024 * 1024 * 1024)); then
    printf 'WARNING: fewer than 25 GiB are available at %s; preserve generations and monitor capacity.\n' \
      "$capacity_path" >&2
  fi
done

printf '\nGenerations\n'
sudo -n nix-env --profile /nix/var/nix/profiles/system --list-generations 2>/dev/null || \
  printf 'System generations: root access required to inspect\n'
printf 'Rollback: keep older system generations and use the systemd-boot menu if required.\n'

printf '\nStorage and UEFI boot inventory\n'
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL
findmnt --real
if [[ -d /sys/firmware/efi ]]; then
  printf 'UEFI runtime: present\n'
else
  printf 'UEFI runtime: NOT PRESENT\n' >&2
fi
if ! sudo -n bootctl status 2>/dev/null; then
  printf 'systemd-boot status: root access required to inspect the protected ESP\n'
fi
printf 'Tracked hardware configuration checksum\n'
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

printf '\nRequired independent backup scope\n'
printf '%s\n' \
  '/home/tristan' '/home/tristan/Projects' '/home/tristan/.ssh' \
  '/etc/nixos/secrets' "$repo_root/hardware-configuration.nix" \
  '/etc/NetworkManager/system-connections/towerofdoom.nmconnection' \
  '/etc/ssh/ssh_host_*' \
  'the preceding two paths are the only additional /etc identities preserved' \
  'repository commit and any uncommitted patch' \
  'browser data, Obsidian vaults, and all other non-reproducible local data'
printf '\nRequired backup command: scripts/backup-for-reinstall.sh\n'
printf 'Fixed destination: /mnt/infernalnexus/nas1/backup\n'
printf '\nPRE-WIPE BOOTSTRAP GATE\n'
printf '%s\n' \
  'Independently confirm first-boot wired access or retrievable Wi-Fi credentials.' \
  'Independently confirm the Infernalnexus SMB username/password is retrievable.' \
  'The SMB credential inside the NAS backup cannot bootstrap access to that same NAS.' \
  'If either dependency is unavailable: DO NOT WIPE YET.' \
  'Do not copy credentials to the Ventoy stick or create another secret archive.'
printf '%s\n' \
  'A completed backup set must be manually inspected before wiping.' \
  'This read-only preflight does not create or prove a backup merely by seeing its folder.' \
  'Follow the single canonical procedure in docs/reinstall.md.'
