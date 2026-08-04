#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$script_dir/release-environment.sh"

case $# in
0)
  exec nix-shell "$HELIX_REPO_ROOT/shell.nix"
  ;;
2)
  if [[ $1 != --run ]]; then
    printf 'Usage: %s [--run COMMAND]\n' "${0##*/}" >&2
    exit 2
  fi
  exec nix-shell "$HELIX_REPO_ROOT/shell.nix" --run "$2"
  ;;
*)
  printf 'Usage: %s [--run COMMAND]\n' "${0##*/}" >&2
  exit 2
  ;;
esac
