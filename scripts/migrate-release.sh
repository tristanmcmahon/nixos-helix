#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
release_file=$repo_root/release.nix
root_channel=/nix/var/nix/profiles/per-user/root/channels/nixos

expected_release=$(nix-instantiate --eval --raw -E "(import $release_file).nixosRelease")
upgrade_state_version=$(nix-instantiate --eval --raw -E "(import $release_file).stateVersion")
channel_url=$(nix-instantiate --eval --raw -E "(import $release_file).channelUrl")

detect_release() {
  if [[ -r $root_channel/default.nix ]]; then
    NIX_PATH="nixpkgs=$root_channel" \
      nix-instantiate --eval --raw -E '(import <nixpkgs> {}).lib.trivial.release'
  else
    printf 'unavailable\n'
  fi
}

print_plan() {
  local current_release=$1
  printf 'cleanup-action=stop\n'
  if [[ $current_release == "$expected_release" ]]; then
    printf 'channel-update=not-required\n'
  else
    printf 'channel-update=required\n'
  fi
  printf 'cleanup-restore=sudo systemctl start helix-nix-cleanup.timer\n'
}

if [[ ${1:-} == --plan ]]; then
  [[ $# -le 2 ]] || {
    printf 'Usage: %s [--plan [CURRENT_RELEASE]]\n' "${0##*/}" >&2
    exit 2
  }
  print_plan "${2:-$(detect_release)}"
  exit 0
elif [[ $# -ne 0 ]]; then
  printf 'Usage: %s [--plan [CURRENT_RELEASE]]\n' "${0##*/}" >&2
  exit 2
fi

current_release=$(detect_release)
cat <<EOF
MAJOR NIXOS RELEASE UPGRADE
Current: $current_release
Target:  $expected_release
system.stateVersion remains $upgrade_state_version
This changes the kernel, drivers, desktop packages and system closure.

The cleanup timer will be stopped during qualification. Existing generations
and store paths will not be deleted. Root authentication is required.
EOF

sudo systemctl stop helix-nix-cleanup.timer
if systemctl is-active --quiet helix-nix-cleanup.timer; then
  printf 'ERROR: cleanup timer remains active after stop.\n' >&2
  exit 1
fi
printf 'Cleanup timer is stopped for qualification.\n'

if [[ $current_release != "$expected_release" ]]; then
  printf '\nType MIGRATE HELIX TO %s to continue: ' "$expected_release"
  IFS= read -r confirmation
  if [[ $confirmation != "MIGRATE HELIX TO $expected_release" ]]; then
    printf 'Migration cancelled; no channel state was changed. Cleanup remains stopped.\n'
    printf 'Restore it with: sudo systemctl start helix-nix-cleanup.timer\n'
    exit 1
  fi
fi

if [[ $current_release == "$expected_release" ]]; then
  printf 'Root already selects NixOS %s; no channel update is needed.\n' "$expected_release"
else
  sudo nix-channel --add "$channel_url" nixos
  sudo nix-channel --update nixos
fi

selected_version=$(
  sudo env "NIX_PATH=nixpkgs=$root_channel" \
    nix-instantiate --eval --raw -E '(import <nixpkgs> {}).lib.version'
)
selected_release=$(
  NIX_PATH="nixpkgs=$root_channel" \
    nix-instantiate --eval --raw -E '(import <nixpkgs> {}).lib.trivial.release'
)
if [[ $selected_release != "$expected_release" ]]; then
  printf 'ERROR: root channel reports %s after migration; expected %s.\n' \
    "$selected_release" "$expected_release" >&2
  exit 1
fi

printf '\nRoot channel qualification target: %s\n' "$selected_version"
printf 'Cleanup remains stopped until qualification completes.\n'
printf 'Restore it later with: sudo systemctl start helix-nix-cleanup.timer\n'
