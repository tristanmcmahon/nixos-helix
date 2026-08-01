#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s {dry-build|build|test|switch}\n' "${0##*/}" >&2
  exit 2
fi

case $1 in
dry-build | build | test | switch)
  action=$1
  ;;
*)
  printf 'Usage: %s {dry-build|build|test|switch}\n' "${0##*/}" >&2
  exit 2
  ;;
esac

printf 'Configuration: %s/configuration.nix\n' "$repo_root"
printf 'Action: %s\n' "$action"

if [[ $action == dry-build ]]; then
  nixos-rebuild "$action" \
    -I "nixos-config=$repo_root/configuration.nix"
else
  sudo nixos-rebuild "$action" \
    -I "nixos-config=$repo_root/configuration.nix"
fi
