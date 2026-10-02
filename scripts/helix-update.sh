#!/usr/bin/env bash

set -euo pipefail

repo=/home/tristan/Projects/nixos-helix
cd "$repo"

# Never let repository-local Git configuration run commands here.
if [[ -n $(git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
  status --porcelain --untracked-files=normal) ]]; then
  printf 'Refusing to update: %s has uncommitted or untracked files.\n' "$repo" >&2
  exit 1
fi

run_build() {
  if command -v nom >/dev/null 2>&1; then "$@" 2>&1 | nom; else "$@"; fi
}

temporary_directory=$(mktemp -d)
out_link="$temporary_directory/system"
channels_profile=/nix/var/nix/profiles/per-user/root/channels
previous_channels=$(readlink "$channels_profile")
previous_channel_generation=$(sed -E 's/^channels-([0-9]+)-link$/\1/' <<<"$previous_channels")
[[ $previous_channel_generation =~ ^[0-9]+$ ]] || {
  printf 'Unexpected root channel profile link: %s\n' "$previous_channels" >&2
  exit 1
}
update_completed=0

# A failed update must not leave the advanced channel selected for the next
# manual rebuild. Restore the exact previous channel generation unless the new
# system was registered and switched successfully.
finish() {
  if ((update_completed == 0)) && [[ $(readlink "$channels_profile") != "$previous_channels" ]]; then
    printf 'Update did not complete; restoring root channel generation %s...\n' \
      "$previous_channel_generation" >&2
    sudo nix-env --profile "$channels_profile" --switch-generation "$previous_channel_generation"
  fi
  rm -rf -- "$temporary_directory"
}
trap finish EXIT

printf 'Updating the root NixOS channel...\n'
sudo nix-channel --update nixos
# The checkout, not the Nix store, provides this file at runtime.
# shellcheck source=/dev/null
source "$repo/scripts/release-environment.sh"
printf 'Running repository validation...\n'
./scripts/check.sh
printf 'Building candidate system...\n'
run_build nix-build --out-link "$out_link" '<nixpkgs/nixos>' -A system
candidate=$(readlink -f "$out_link")
printf 'Candidate package changes:\n'
nvd diff /run/current-system "$candidate"
previous=$(readlink -f /run/current-system)
printf 'Test-activating candidate...\n'
sudo "$candidate/bin/switch-to-configuration" test
printf 'Running candidate runtime health gate...\n'
if ! "$candidate/sw/bin/helix-health" --check; then
  printf 'Candidate health check failed; restoring previous running configuration...\n' >&2
  sudo "$previous/bin/switch-to-configuration" test
  exit 1
fi
printf 'Candidate health check passed; registering system generation...\n'
sudo nix-env --profile /nix/var/nix/profiles/system --set "$candidate"
printf 'Selecting registered generation for boot...\n'
if ! sudo "$candidate/bin/switch-to-configuration" switch; then
  printf 'Final activation failed; restoring previous system generation...\n' >&2
  sudo nix-env --profile /nix/var/nix/profiles/system --set "$previous"
  sudo "$previous/bin/switch-to-configuration" switch
  exit 1
fi
update_completed=1
profile=$(readlink -f /nix/var/nix/profiles/system)
generation=$(sudo nix-env --profile /nix/var/nix/profiles/system --list-generations |
  awk '$0 ~ /current/ { print $1 }')
printf 'Active system generation: %s (%s)\n' "$generation" "$profile"
printf 'Rollback: sudo nixos-rebuild switch --rollback\n'
