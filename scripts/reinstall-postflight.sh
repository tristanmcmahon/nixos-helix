#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
expected_release=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).nixosRelease")

printf '%s\n' 'HELIX REINSTALL POSTFLIGHT — READ ONLY'
printf 'Canonical checkout: %s\n' "$repo_root"
[[ $repo_root == /home/tristan/Projects/nixos-helix ]]
[[ -d $repo_root/.git ]]
printf 'Installed checkout commit: %s\n' "$(git -C "$repo_root" rev-parse HEAD)"
printf '/etc/nixos is an installer fallback, not the canonical checkout.\n'

selected_release=$(nixos-version | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
printf 'NixOS release: %s\n' "$selected_release"
[[ $selected_release == "$expected_release" ]]
printf 'Running:    '; readlink -f /run/current-system
printf 'Persistent: '; readlink -f /nix/var/nix/profiles/system
uname -a

printf '\nFilesystems and generated hardware\n'
findmnt --real
lsblk -f
rg -n 'fileSystems|device = "/dev/disk/by-uuid/' "$repo_root/hardware-configuration.nix"

printf '\nRuntime data (contents are never printed)\n'
test -s /home/tristan/.ssh/authorized_keys
grep -Eq '^[[:space:]]*[^#[:space:]]' /home/tristan/.ssh/authorized_keys
sudo stat -c 'NAS credential: %U:%G %a' /etc/nixos/secrets/infernalnexus-smb

printf '\nCritical services and hardware\n'
systemctl --failed
systemctl is-active display-manager.service sshd.service
systemctl is-enabled mnt-infernalnexus-nas1.automount
systemctl is-active mnt-infernalnexus-nas1.automount
systemctl cat mnt-infernalnexus-nas1.automount
nvidia-smi
wpctl status
systemctl status ckb-next.service --no-pager
ss -lntup

printf '\nExecutable inventory\n'
for command in vi vim git gh code codex ghostty steam mangohud op 1password \
  ckb-next vlc mpv haruna strawberry; do
  command -v "$command" >/dev/null
  printf '%s: %s\n' "$command" "$(command -v "$command")"
done

printf '\nDo not remove installation media or verified backups until all hardware and data checks pass.\n'
