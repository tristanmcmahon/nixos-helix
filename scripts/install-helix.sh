#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

phase() {
  printf '\n===== %s =====\n' "$1"
}

confirm() {
  local prompt=$1
  local answer
  printf '%s [y/N] ' "$prompt"
  IFS= read -r answer || return 1
  [[ $answer == y || $answer == Y || $answer == yes || $answer == YES ]]
}

allow_missing_ssh_key=0
case ${1:-} in
"") ;;
--allow-missing-ssh-key) allow_missing_ssh_key=1 ;;
*) die 'Usage: install-helix.sh [--allow-missing-ssh-key]' ;;
esac

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
release=$(nix-instantiate --eval --strict release.nix)
expected_release=$(nix-instantiate --eval --raw -E '(import ./release.nix).nixosRelease')
state_version=$(nix-instantiate --eval --raw -E '(import ./release.nix).stateVersion')
selected_release=$(nix-instantiate --eval --raw -E \
  'let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; }; in system.config.system.nixos.release')

phase 'Repository preflight'
printf 'Repository: %s\n' "$repo_root"
printf 'Branch: %s\n' "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || printf '(detached HEAD)')"
printf 'Commit: %s\n' "$(git rev-parse HEAD)"
if [[ -n $(git status --short) ]]; then
  printf 'State: dirty\n' >&2
  git status --short >&2
  die 'Installation requires a clean checkout; update or commit it separately.'
fi
printf 'State: clean\n'
git remote get-url origin >/dev/null 2>&1 || die "This checkout has no 'origin' remote."

phase 'Release preflight'
printf 'Release contract: %s\n' "$release"
printf 'Expected NixOS release: %s\n' "$expected_release"
printf 'Selected NixOS release: %s\n' "$selected_release"
printf 'Persistent state version: %s\n' "$state_version"
[[ $selected_release == "$expected_release" ]] ||
  die "Select the nixos-26.05 channel before installation; found $selected_release."
[[ $state_version == 25.11 ]] || die 'The persistent state version changed unexpectedly.'

phase 'Hardware and configuration preflight'
[[ -s hardware-configuration.nix ]] || die 'hardware-configuration.nix is missing or empty.'
git ls-files --error-unmatch hardware-configuration.nix >/dev/null 2>&1 ||
  die 'hardware-configuration.nix is not tracked by Git.'
[[ -x scripts/check.sh && -x scripts/rebuild.sh ]] || die 'Validation helpers are unavailable.'

authorized_keys=/home/tristan/.ssh/authorized_keys
if [[ ! -s $authorized_keys ]] || ! grep -Eq '^[[:space:]]*[^#[:space:]]' "$authorized_keys"; then
  if ((allow_missing_ssh_key)); then
    printf 'WARNING: no SSH public key is installed; this is a deliberate local-console-only installation.\n' >&2
  else
    die 'No SSH public key is installed; key-only SSH would accept no remote user. Use --allow-missing-ssh-key only for a deliberate local-console-only installation.'
  fi
fi

credential=/etc/nixos/secrets/infernalnexus-smb
if sudo test -f "$credential"; then
  credential_metadata=$(sudo stat -c '%U:%G %a' "$credential")
  [[ $credential_metadata == 'root:root 600' ]] ||
    die "$credential must be owned by root:root with mode 0600."
  printf 'NAS credentials: present with protected ownership and mode (contents not read)\n'
else
  printf 'WARNING: NAS credentials are absent. Evaluation and activation are safe, but access will fail.\n' >&2
fi
printf 'NAS protocol: SMB 2.0 with NTLMSSP\n'

phase 'Complete non-activating validation'
./scripts/check.sh
./scripts/rebuild.sh dry-build

phase 'Temporary activation'
if ! confirm 'Temporarily activate the validated configuration?'; then
  printf 'Cancelled before activation.\n'
  exit 0
fi
./scripts/rebuild.sh test

phase 'Focused runtime verification'
systemctl is-enabled display-manager.service
systemctl is-active display-manager.service
systemctl is-active sshd.service
ss -ltn | grep -Eq '(^|[[:space:]])[^[:space:]]*:22[[:space:]]'
sshd -T | grep -E '^(permitrootlogin no|pubkeyauthentication yes|passwordauthentication no|kbdinteractiveauthentication no)$'
systemctl is-enabled mnt-infernalnexus-nas1.automount
systemctl is-active mnt-infernalnexus-nas1.automount
systemctl cat mnt-infernalnexus-nas1.automount
systemctl cat mnt-infernalnexus-nas1.mount
systemctl is-enabled helix-nix-cleanup.timer
test -r /run/current-system/etc/systemd/user/helix-abyss-theme.service
grep -qF 'ConditionUser=tristan' /run/current-system/etc/systemd/user/helix-ghostty-config.service
for command in vi vim code codex gh git; do
  command -v "$command" >/dev/null || die "$command is unavailable after test activation."
done
printf 'The NAS automount should be active (waiting); it was not triggered by this installer.\n'

phase 'Persistent activation'
if ! confirm 'Make the tested configuration the persistent boot default?'; then
  printf 'Temporary activation retained; persistent boot default unchanged.\n'
  exit 0
fi
./scripts/rebuild.sh switch

phase 'Optional reboot'
if confirm 'Reboot now?'; then
  sudo reboot
else
  printf 'Reboot later with: sudo reboot\n'
fi
