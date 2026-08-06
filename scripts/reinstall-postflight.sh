#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
expected_release=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).nixosRelease")
fresh_state_version=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).freshStateVersion")
preserved_hardware=/var/lib/helix-install/hardware-configuration.nix
canonical_backup_root=/mnt/infernalnexus/nas1/backup
backup_root=$canonical_backup_root

printf '%s\n' 'HELIX REINSTALL POSTFLIGHT — READ ONLY'
printf 'Canonical checkout: %s\n' "$repo_root"
[[ $repo_root == /home/tristan/Projects/nixos-helix ]]
[[ -d $repo_root/.git ]]
printf 'Installed checkout commit: %s\n' "$(git -C "$repo_root" rev-parse HEAD)"
approved_commit=$(</var/lib/helix-install/approved-commit)
[[ $(git -C "$repo_root" rev-parse HEAD) == "$approved_commit" ]]
printf 'Origin/main commit: %s\n' "$(git -C "$repo_root" rev-parse origin/main)"
printf '/etc/nixos is an installer fallback, not the canonical checkout.\n'

selected_release=$(nixos-version | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
printf 'NixOS release: %s\n' "$selected_release"
[[ $selected_release == "$expected_release" ]]
fresh_state_marker=/etc/helix/fresh-install-state-version
printf 'Fresh-install state marker: '
cat "$fresh_state_marker"
grep -qxF "$fresh_state_version" "$fresh_state_marker"
printf 'Running:    '; readlink -f /run/current-system
printf 'Persistent: '; readlink -f /nix/var/nix/profiles/system
uname -a

printf '\nFilesystems and generated hardware\n'
"$repo_root/scripts/verify-hardware-continuity.sh" \
  "$preserved_hardware" "$repo_root/hardware-configuration.nix" \
  /etc/nixos/hardware-configuration.nix
(cd /var/lib/helix-install && sha256sum --check hardware-configuration.nix.sha256)
findmnt --real
lsblk -f
rg -n 'fileSystems|device = "/dev/disk/by-uuid/' "$repo_root/hardware-configuration.nix"
mapfile -t configured_uuids < <(grep -oE '/dev/disk/by-uuid/[^"[:space:]]+' \
  "$repo_root/hardware-configuration.nix" | sed 's#.*/##' | sort -u)
for configured_uuid in "${configured_uuids[@]}"; do
  [[ -e /dev/disk/by-uuid/$configured_uuid ]]
  printf 'Configured UUID present: %s\n' "$configured_uuid"
done
for required_mount in / /boot; do
  mount_source=$(findmnt -n -o SOURCE -T "$required_mount")
  mount_uuid=$(lsblk -n -o UUID "$mount_source" | head -n 1)
  [[ -n $mount_uuid ]]
  printf '%s\n' "${configured_uuids[@]}" | grep -qxF "$mount_uuid"
  printf 'Mounted %s uses configured UUID: %s\n' "$required_mount" "$mount_uuid"
done
printf 'Review the inventory above and confirm no retired or unexpected disk is mounted.\n'

printf '\nRuntime data (contents are never printed)\n'
test -s /home/tristan/.ssh/authorized_keys
grep -Eq '^[[:space:]]*[^#[:space:]]' /home/tristan/.ssh/authorized_keys
sudo stat -c 'NAS credential: %U:%G %a' /etc/nixos/secrets/infernalnexus-smb
[[ $(sudo stat -c '%U:%G %a' /etc/nixos/secrets/infernalnexus-smb) == 'root:root 600' ]]

printf '\nCritical services and hardware\n'
systemctl --failed
systemctl is-active display-manager.service sshd.service
systemctl is-enabled mnt-infernalnexus-nas1.automount
systemctl is-active mnt-infernalnexus-nas1.automount
[[ $(systemctl show mnt-infernalnexus-nas1.automount -P SubState) == waiting ]]
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

printf '\nBackup preservation\n'
stat -- /mnt/infernalnexus/nas1 >/dev/null
mountpoint -q /mnt/infernalnexus/nas1
[[ $(findmnt -nro FSTYPE --target /mnt/infernalnexus/nas1) == cifs ]]
backup_source=$(findmnt -nro SOURCE --target /mnt/infernalnexus/nas1)
[[ ${backup_source%/} == //192.168.1.8/nas1 ]]
[[ -d $backup_root && -r $backup_root ]]
mapfile -t completed_sets < <(
  find "$backup_root" -mindepth 1 -maxdepth 1 -type d \
    -name 'helix-reinstall-*' ! -name '*.INCOMPLETE' -printf '%f\n' | sort -r
)
newest_completed=
for set_name in "${completed_sets[@]}"; do
  candidate=$backup_root/$set_name
  if [[ -f $candidate/COMPLETE && -f $candidate/SHA256SUMS && \
        -f $candidate/BACKUP-README.txt && -f $candidate/home-tristan.tar && \
        -f $candidate/etc-nixos-secrets.tar ]]; then
    newest_completed=$candidate
    break
  fi
done
[[ -n $newest_completed ]] || {
  printf 'No structurally complete canonical reinstall backup was found.\n' >&2
  exit 1
}
printf 'Newest completed canonical backup: %s\n' "$newest_completed"
printf 'Preserved artifacts: COMPLETE, SHA256SUMS, README, home archive, secrets archive\n'

printf '\nDo not remove the canonical NAS backup until all hardware and data checks pass.\n'
