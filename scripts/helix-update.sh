#!/usr/bin/env bash

set -euo pipefail

repo=/home/tristan/Projects/nixos-helix
cd "$repo"

if [[ -n $(git status --porcelain --untracked-files=normal) ]]; then
  printf 'Refusing to update: %s has uncommitted or untracked files.\n' "$repo" >&2
  exit 1
fi

run_build() {
  if command -v nom >/dev/null 2>&1; then "$@" 2>&1 | nom; else "$@"; fi
}

printf 'Updating the root Nix channels...\n'
sudo nix-channel --update
printf 'Running repository validation...\n'
./scripts/check.sh
printf 'Building candidate system...\n'
out_link=$(mktemp -u /tmp/helix-update-system.XXXXXX)
trap 'rm -f -- "$out_link"' EXIT
run_build nix-build --out-link "$out_link" '<nixpkgs/nixos>' -A system \
  -I "nixos-config=$repo/configuration.nix"
candidate=$(readlink -f "$out_link")
printf 'Candidate package changes:\n'
nvd diff /run/current-system "$candidate"
printf 'Test-activating candidate...\n'
sudo "$candidate/bin/switch-to-configuration" test
printf 'Test activation succeeded; selecting it for boot...\n'
sudo "$candidate/bin/switch-to-configuration" switch
profile=$(readlink -f /nix/var/nix/profiles/system)
generation=$(nix-env --profile /nix/var/nix/profiles/system --list-generations |
  awk '$0 ~ /current/ { print $1 }')
printf 'Active system generation: %s (%s)\n' "$generation" "$profile"
printf 'Rollback: sudo nixos-rebuild switch --rollback\n'
