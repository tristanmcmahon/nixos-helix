#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
release_file=$repo_root/release.nix
root_channel=/nix/var/nix/profiles/per-user/root/channels/nixos
qualification_hold=/var/lib/helix/release-qualification

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
running_system=$(readlink -f /run/current-system)
cat <<EOF
MAJOR NIXOS RELEASE UPGRADE
Current: $current_release
Target:  $expected_release
system.stateVersion remains $upgrade_state_version
This changes the kernel, drivers, desktop packages and system closure.

The cleanup timer will be stopped during qualification. Existing generations
and store paths will not be deleted. Root authentication is required.
EOF

if [[ -d $qualification_hold ]]; then
  saved_source=$(sudo cat "$qualification_hold/source-system-path" 2>/dev/null || true)
  [[ $saved_source == "$running_system" ]] || {
    printf 'ERROR: an incompatible qualification hold already exists at %s.\n' \
      "$qualification_hold" >&2
    exit 1
  }
else
  source_generation=
  for generation_link in /nix/var/nix/profiles/system-*-link; do
    if [[ $(readlink -f "$generation_link") == "$running_system" ]]; then
      source_generation=${generation_link##*/system-}
      source_generation=${source_generation%-link}
    fi
  done
  [[ -n $source_generation ]]
  metadata_directory=$(mktemp -d)
  trap 'rm -rf -- "$metadata_directory"' EXIT
  date --iso-8601=seconds >"$metadata_directory/started-at"
  printf '%s\n' "$current_release" >"$metadata_directory/source-release"
  printf '%s\n' "$expected_release" >"$metadata_directory/target-release"
  printf '%s\n' "$running_system" >"$metadata_directory/source-system-path"
  printf '%s\n' "$source_generation" >"$metadata_directory/source-generation"
  uname -r >"$metadata_directory/source-kernel"
  nixos-version >"$metadata_directory/source-nixos-version"
  printf '%s\n' "$root_channel" >"$metadata_directory/source-channel"
  sudo install -d -m 0755 "$qualification_hold"
  for metadata in "$metadata_directory"/*; do
    sudo install -m 0444 "$metadata" "$qualification_hold/${metadata##*/}"
  done
fi

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
