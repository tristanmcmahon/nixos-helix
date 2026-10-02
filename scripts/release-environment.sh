#!/usr/bin/env bash

# Source this file from repository scripts to select the Nixpkgs tree pinned in
# nixpkgs.json (fetched once into the Nix store). HELIX_NIXPKGS_PATH overrides
# it with an explicit tree, for example in the graphical installer.
helix_script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
HELIX_REPO_ROOT=$(cd -- "$helix_script_dir/.." && pwd)
if [[ -n ${HELIX_NIXPKGS_PATH:-} ]]; then
  HELIX_SELECTED_NIXPKGS=$HELIX_NIXPKGS_PATH
else
  # nix-prefetch-url always realises the tarball in the store and verifies the
  # pinned hash; evaluating fetchTarball alone may leave the path unrealised.
  helix_pin_url=$(nix-instantiate --eval --raw -E "(builtins.fromJSON (builtins.readFile $HELIX_REPO_ROOT/nixpkgs.json)).url")
  helix_pin_sha256=$(nix-instantiate --eval --raw -E "(builtins.fromJSON (builtins.readFile $HELIX_REPO_ROOT/nixpkgs.json)).sha256")
  HELIX_SELECTED_NIXPKGS=$(nix-prefetch-url --unpack --name source --print-path \
    "$helix_pin_url" "$helix_pin_sha256" 2>/dev/null | tail -n 1) || {
    printf 'ERROR: could not fetch the Nixpkgs pinned in %s/nixpkgs.json.\n' "$HELIX_REPO_ROOT" >&2
    # shellcheck disable=SC2317 # exit is the direct-execution fallback.
    return 1 2>/dev/null || exit 1
  }
fi

if [[ ! -r $HELIX_SELECTED_NIXPKGS/default.nix ]]; then
  printf 'ERROR: selected Nixpkgs source is unavailable at %s.\n' \
    "$HELIX_SELECTED_NIXPKGS" >&2
  printf 'Check nixpkgs.json or set HELIX_NIXPKGS_PATH to a readable Nixpkgs tree.\n' >&2
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
export HELIX_REPO_ROOT HELIX_SELECTED_NIXPKGS HELIX_EXPECTED_RELEASE HELIX_SELECTED_RELEASE
printf 'Selected Nixpkgs: %s\n' "$HELIX_SELECTED_NIXPKGS"

if [[ $HELIX_SELECTED_RELEASE != "$HELIX_EXPECTED_RELEASE" ]]; then
  printf 'Expected release: %s\n' "$HELIX_EXPECTED_RELEASE" >&2
  printf 'Selected release: %s\n' "$HELIX_SELECTED_RELEASE" >&2
  printf 'Nixpkgs source:   %s\n\n' "$HELIX_SELECTED_NIXPKGS" >&2
  printf 'ERROR: Helix requires a NixOS %s Nixpkgs tree.\n' "$HELIX_EXPECTED_RELEASE" >&2
  printf 'Pin a NixOS %s release in nixpkgs.json or provide HELIX_NIXPKGS_PATH.\n' "$HELIX_EXPECTED_RELEASE" >&2
  # shellcheck disable=SC2317 # exit is the direct-execution fallback.
  return 1 2>/dev/null || exit 1
fi
