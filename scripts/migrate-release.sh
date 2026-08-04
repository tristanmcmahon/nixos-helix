#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
release_file=$repo_root/release.nix
root_channel=/nix/var/nix/profiles/per-user/root/channels/nixos

expected_release=$(nix-instantiate --eval --raw -E "(import $release_file).nixosRelease")
state_version=$(nix-instantiate --eval --raw -E "(import $release_file).stateVersion")
channel_url=$(nix-instantiate --eval --raw -E "(import $release_file).channelUrl")
current_release=unavailable
if [[ -r $root_channel/default.nix ]]; then
  current_release=$(
    NIX_PATH="nixpkgs=$root_channel" \
      nix-instantiate --eval --raw -E '(import <nixpkgs> {}).lib.trivial.release'
  )
fi

cat <<EOF
MAJOR NIXOS RELEASE UPGRADE
Current: $current_release
Target:  $expected_release
system.stateVersion remains $state_version
This changes the kernel, drivers, desktop packages and system closure.

The cleanup timer will be stopped during qualification. Existing generations
and store paths will not be deleted. Root authentication is required.
EOF

if [[ $current_release == "$expected_release" ]]; then
  printf '\nRoot already selects NixOS %s; no channel update is needed.\n' "$expected_release"
  exit 0
fi

printf '\nType MIGRATE HELIX TO %s to continue: ' "$expected_release"
IFS= read -r confirmation
if [[ $confirmation != "MIGRATE HELIX TO $expected_release" ]]; then
  printf 'Migration cancelled; no channel state was changed.\n'
  exit 1
fi

sudo systemctl stop helix-nix-cleanup.timer
sudo nix-channel --add "$channel_url" nixos
sudo nix-channel --update nixos

selected_version=$(
  sudo env "NIX_PATH=nixpkgs=$root_channel" \
    nix-instantiate --eval --raw -E '(import <nixpkgs> {}).lib.version'
)
selected_release=$(
  NIX_PATH="nixpkgs=$root_channel" \
    nix-instantiate --eval --raw -E '(import <nixpkgs> {}).lib.trivial.release'
)
if [[ $selected_release != "$expected_release" ]]; then
  printf 'ERROR: root channel reports %s after update; expected %s.\n' \
    "$selected_release" "$expected_release" >&2
  exit 1
fi

printf '\nRoot channel migration succeeded: %s\n' "$selected_version"
printf 'Cleanup remains stopped until qualification completes.\n'
printf 'Restore it later with: sudo systemctl start helix-nix-cleanup.timer\n'
