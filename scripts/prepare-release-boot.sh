#!/usr/bin/env bash

set -euo pipefail

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-qualification-lib.sh"
# shellcheck disable=SC2154 # Assigned by release-qualification-lib.sh.
qualification_hold=${qualification_hold:?}
# shellcheck disable=SC2154 # Assigned by release-qualification-lib.sh.
qualification_gcroot=${qualification_gcroot:?}

if [[ ${1:-} == --plan && $# -eq 1 ]]; then
  qualification_workflow_plan
  exit 0
elif [[ $# -ne 0 ]]; then
  die 'Usage: prepare-release-boot.sh [--plan]'
fi

cd "$repo_root"
# shellcheck source=/dev/null
source "$repo_root/scripts/release-environment.sh"
expected_release=$HELIX_EXPECTED_RELEASE
source_release=$(nixos-version | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
running_system=$(readlink -f /run/current-system)
persistent_system=$(readlink -f /nix/var/nix/profiles/system)
source_generation=
source_generation_matches=0
shopt -s nullglob
for link in /nix/var/nix/profiles/system-*-link; do
  if [[ $(readlink -f "$link") == "$running_system" ]]; then
    source_generation=${link##*/system-}
    source_generation=${source_generation%-link}
    ((source_generation_matches += 1))
  fi
done
[[ $source_generation_matches -eq 1 ]] || die 'The running system does not match exactly one visible generation.'
[[ -z $(git status --short) ]] || die 'Release preparation requires a clean checkout.'

printf '%s\n' 'MAJOR RELEASE BOOT QUALIFICATION' \
  "Source release: $source_release" "Target release: $expected_release" \
  "Running system: $running_system" "Persistent system: $persistent_system"

existing_root=
if [[ -e $qualification_gcroot || -L $qualification_gcroot ]]; then
  existing_root=$(readlink -f "$qualification_gcroot" || true)
fi
gcroot_plan=$(qualification_gcroot_plan "$existing_root" "$running_system")
[[ $gcroot_plan != refuse ]] || die "$qualification_gcroot already protects a different closure."

metadata_directory=$(mktemp -d)
trap 'rm -rf -- "$metadata_directory"' EXIT
date --iso-8601=seconds >"$metadata_directory/started-at"
printf '%s\n' "$source_release" >"$metadata_directory/source-release"
printf '%s\n' "$expected_release" >"$metadata_directory/target-release"
printf '%s\n' "$running_system" >"$metadata_directory/source-system-path"
printf '%s\n' "$source_generation" >"$metadata_directory/source-generation"
uname -r >"$metadata_directory/source-kernel"
nixos-version >"$metadata_directory/source-nixos-version"
printf '%s\n' "$HELIX_SELECTED_NIXPKGS" >"$metadata_directory/source-channel"

sudo install -d -m 0755 "$qualification_hold"
for metadata in "$metadata_directory"/*; do
  sudo install -m 0444 "$metadata" "$qualification_hold/${metadata##*/}"
done
sudo systemctl stop helix-nix-cleanup.timer
systemctl is-active --quiet helix-nix-cleanup.timer && die 'Cleanup timer remains active.'

if [[ $gcroot_plan == create ]]; then
  sudo nix-store --add-root "$qualification_gcroot" -r "$running_system" >/dev/null
fi
[[ $(readlink -f "$qualification_gcroot") == "$running_system" ]] || die 'Rollback GC root verification failed.'
[[ -e /nix/var/nix/profiles/system-$source_generation-link ]] || die 'Rollback generation disappeared.'
sudo test -r "/boot/loader/entries/nixos-generation-$source_generation.conf" ||
  die 'The running rollback generation has no visible systemd-boot entry.'

./scripts/reinstall-preflight.sh
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh dry-build
candidate=$(./scripts/rebuild.sh build | sed -n 's/^Done. The new configuration is //p' | tail -n 1)
[[ -n $candidate && -x $candidate/bin/switch-to-configuration ]] || die 'Candidate closure was not identified.'
printf '%s\n' "$candidate" | sudo tee "$qualification_hold/candidate-system-path" >/dev/null
sudo chmod 0444 "$qualification_hold/candidate-system-path"
./scripts/rebuild.sh dry-activate

printf 'Candidate closure: %s\n' "$candidate"
"$candidate/sw/bin/nixos-version" || true
printf 'Type PREPARE HELIX %s BOOT to continue: ' "$expected_release"
IFS= read -r confirmation
[[ $confirmation == "PREPARE HELIX $expected_release BOOT" ]] || die 'Cancelled before boot-profile change.'
./scripts/rebuild.sh boot
[[ $(readlink -f /nix/var/nix/profiles/system) == "$candidate" ]] || die 'Persistent profile does not select the candidate.'
candidate_generation=
for link in /nix/var/nix/profiles/system-*-link; do
  if [[ $(readlink -f "$link") == "$candidate" ]]; then
    candidate_generation=${link##*/system-}
    candidate_generation=${candidate_generation%-link}
  fi
done
[[ -n $candidate_generation ]]
sudo test -r "/boot/loader/entries/nixos-generation-$candidate_generation.conf" ||
  die 'The candidate generation has no visible systemd-boot entry.'

printf '%s\n' \
  'The candidate is now the default boot generation but is not active.' \
  'Reboot is a separate human action.' \
  'Select the previous generation in systemd-boot if the candidate fails.'
