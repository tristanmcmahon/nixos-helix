#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-qualification-lib.sh"
# shellcheck disable=SC2154 # Assigned by release-qualification-lib.sh.
qualification_hold=${qualification_hold:?}
expected_release=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).nixosRelease")
record_success=0
case ${1:-} in
"") ;;
--record-success) record_success=1 ;;
*) printf 'Usage: %s [--record-success]\n' "${0##*/}" >&2; exit 2 ;;
esac
running=$(readlink -f /run/current-system)
persistent=$(readlink -f /nix/var/nix/profiles/system)

[[ -d $qualification_hold ]]
[[ $running == "$persistent" ]]
[[ $(nixos-version | sed -E 's/^([0-9]+\.[0-9]+).*/\1/') == "$expected_release" ]]
printf 'Kernel: %s\n' "$(uname -r)"
printf 'Booted system: %s\n' "$running"
sudo bootctl status
nvidia_module_version=$(cat /sys/module/nvidia/version)
nvidia_userspace_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
printf 'NVIDIA module/userspace: %s / %s\n' "$nvidia_module_version" "$nvidia_userspace_version"
[[ $nvidia_module_version == "$nvidia_userspace_version" ]]
nvidia-smi
systemctl is-active display-manager.service sshd.service bluetooth.service ckb-next.service
systemctl --user is-active pipewire.service wireplumber.service
test -e /run/current-system/sw/share/wayland-sessions/plasma.desktop
find /run/current-system/sw/share/wayland-sessions -type f -iname '*hyprland*.desktop' -print -quit | grep -q .
sshd -T | tr '[:upper:]' '[:lower:]' | grep -E \
  '^(permitrootlogin no|pubkeyauthentication yes|passwordauthentication no|kbdinteractiveauthentication no)$'
ss -ltn | grep -Eq '(^|[[:space:]])[^[:space:]]*:22[[:space:]]'
failed_units=$(systemctl --failed --no-legend)
[[ -z $failed_units ]]
if systemctl is-active --quiet helix-nix-cleanup.timer; then exit 1; fi
systemctl is-enabled mnt-infernalnexus-nas1.automount
[[ $(systemctl show mnt-infernalnexus-nas1.automount -P SubState) == waiting ]]
for command in vi vim git gh code codex ghostty steam mangohud op 1password ckb-next vlc mpv; do
  command -v "$command" >/dev/null
done
printf 'NAS was not accessed. Run its sustained test separately.\n'
printf 'POST-REBOOT CHECKS PASSED\n'
if ((record_success)); then
  printf '%s\n' "$(date --iso-8601=seconds)" | sudo tee "$qualification_hold/post-reboot-success" >/dev/null
  sudo chmod 0444 "$qualification_hold/post-reboot-success"
  printf 'Success record written after explicit --record-success request.\n'
else
  printf 'Read-only run; repeat with --record-success after reviewing the results.\n'
fi
