#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-environment.sh"

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s {dry-build|build|dry-activate|test|switch}\n' "${0##*/}" >&2
  exit 2
fi

case $1 in
dry-build | build | dry-activate | test | switch)
  action=$1
  ;;
*)
  printf 'Usage: %s {dry-build|build|dry-activate|test|switch}\n' "${0##*/}" >&2
  exit 2
  ;;
esac

printf 'Configuration: %s/configuration.nix\n' "$repo_root"
printf 'NixOS release: %s\n' "$HELIX_SELECTED_RELEASE"
printf 'Action: %s\n' "$action"

run_build() {
  if command -v nom >/dev/null 2>&1; then
    "$@" 2>&1 | nom
  else
    "$@"
  fi
}

if [[ $action == dry-build || $action == build ]]; then
  run_build nixos-rebuild "$action" \
    -I "nixos-config=$repo_root/configuration.nix"
elif [[ $action == dry-activate ]]; then
  system_closure=$(nix-build --no-out-link '<nixpkgs/nixos>' -A system \
    -I "nixos-config=$repo_root/configuration.nix")
  printf 'System closure: %s\n' "$system_closure"
  sudo env STC_DEBUG=1 "$system_closure/bin/switch-to-configuration" dry-activate
else
  run_build sudo nixos-rebuild "$action" \
    -I "nixos-config=$repo_root/configuration.nix"
fi
