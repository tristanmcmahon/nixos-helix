#!/usr/bin/env bash

# Source this file from repository scripts to select the same Nixpkgs tree used
# by root rebuilds. It deliberately never mutates channel state.
helix_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HELIX_REPO_ROOT=$(cd -- "$helix_script_dir/.." && pwd)
HELIX_ROOT_NIXOS_CHANNEL=/nix/var/nix/profiles/per-user/root/channels/nixos
HELIX_SELECTED_NIXPKGS=${HELIX_NIXPKGS_PATH:-$HELIX_ROOT_NIXOS_CHANNEL}

if [[ ! -r $HELIX_SELECTED_NIXPKGS/default.nix ]]; then
  printf 'ERROR: selected Nixpkgs source is unavailable at %s.\n' \
    "$HELIX_SELECTED_NIXPKGS" >&2
  printf 'Restore the root channel or set HELIX_NIXPKGS_PATH to a readable Nixpkgs tree.\n' >&2
  # shellcheck disable=SC2317 # exit is the direct-execution fallback.
  return 1 2>/dev/null || exit 1
fi

HELIX_EXPECTED_RELEASE=$(
  nix-instantiate --eval --raw -E \
    "(import $HELIX_REPO_ROOT/release.nix).nixosRelease"
)
HELIX_SELECTED_NIXPKGS=$(readlink -f "$HELIX_SELECTED_NIXPKGS")
export NIX_PATH="nixpkgs=$HELIX_SELECTED_NIXPKGS:nixos-config=$HELIX_REPO_ROOT/configuration.nix:$HELIX_SELECTED_NIXPKGS"
HELIX_SELECTED_RELEASE=$(
  nix-instantiate --eval --raw -E '(import <nixpkgs> {}).lib.trivial.release'
)
export HELIX_REPO_ROOT HELIX_ROOT_NIXOS_CHANNEL HELIX_SELECTED_NIXPKGS HELIX_EXPECTED_RELEASE HELIX_SELECTED_RELEASE
printf 'Selected Nixpkgs: %s\n' "$HELIX_SELECTED_NIXPKGS"

if [[ $HELIX_SELECTED_RELEASE != "$HELIX_EXPECTED_RELEASE" ]]; then
  printf 'Expected release: %s\n' "$HELIX_EXPECTED_RELEASE" >&2
  printf 'Selected release: %s\n' "$HELIX_SELECTED_RELEASE" >&2
  printf 'Nixpkgs source:   %s\n\n' "$HELIX_SELECTED_NIXPKGS" >&2
  printf 'ERROR: Helix has not yet selected NixOS %s.\n' "$HELIX_EXPECTED_RELEASE" >&2
  printf 'Run the explicit migration command before checking or building.\n' >&2
  # shellcheck disable=SC2317 # exit is the direct-execution fallback.
  return 1 2>/dev/null || exit 1
fi
