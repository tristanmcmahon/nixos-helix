#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-environment.sh"

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s local-llm\n' "${0##*/}" >&2
  exit 2
fi

case $1 in
local-llm)
  profile=$1
  ;;
*)
  printf 'Usage: %s local-llm\n' "${0##*/}" >&2
  exit 2
  ;;
esac

temporary_module=$(mktemp --suffix=.nix)
trap 'rm -f -- "$temporary_module"' EXIT

printf '{ ... }: { imports = [ %s %s ]; }\n' \
  "$repo_root/configuration.nix" \
  "$repo_root/profiles/$profile.nix" >"$temporary_module"

printf 'Checking optional profile: %s\n' "$profile"
nixos-rebuild dry-build \
  -I "nixos-config=$temporary_module"
