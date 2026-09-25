#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-environment.sh"
cd "$repo_root"

mode=quick
if [[ ${1:-} == --full ]]; then
  mode=full
  shift
elif [[ ${1:-} == --quick ]]; then
  shift
fi
if [[ $# -ne 0 ]]; then
  printf 'Usage: %s [--quick|--full]\n' "${0##*/}" >&2
  exit 2
fi

required_tools=(deadnix nixfmt shellcheck statix)
for required_tool in "${required_tools[@]}"; do
  if ! command -v "$required_tool" >/dev/null; then
    printf 'Missing validation tool: %s\n' "$required_tool" >&2
    printf "Run: ./scripts/dev-shell.sh --run './scripts/check.sh'\n" >&2
    exit 1
  fi
done

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT

# shellcheck source=scripts/checks/static.sh
source "$repo_root/scripts/checks/static.sh"

# shellcheck source=scripts/checks/evaluation.sh
source "$repo_root/scripts/checks/evaluation.sh"

if [[ $mode == full ]]; then
  printf 'Running explicit full-system release validation...\n'

  # shellcheck source=scripts/checks/system-build.sh
  source "$repo_root/scripts/checks/system-build.sh"

  # shellcheck source=scripts/checks/desktop.sh
  source "$repo_root/scripts/checks/desktop.sh"

  # shellcheck source=scripts/checks/monitoring.sh
  source "$repo_root/scripts/checks/monitoring.sh"

  # shellcheck source=scripts/checks/network.sh
  source "$repo_root/scripts/checks/network.sh"

  # shellcheck source=scripts/checks/applications.sh
  source "$repo_root/scripts/checks/applications.sh"
else
  printf 'Quick validation passed. Use scripts/check.sh --full for release closure checks.\n'
fi
