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
# Many checks are bare tests; name the one that failed instead of exiting silently.
trap 'printf "check failed: %s line %s: %s\n" "${BASH_SOURCE[0]}" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Fail unless the runtime closure of $1 provides bin/<command> for every
# remaining argument. The closure is queried once.
require_closure_commands() {
  local root=$1 command closure_path closure_output
  shift
  local -a closure
  # A failed store query stops here rather than reading as a missing command.
  closure_output=$(nix-store -qR "$root")
  mapfile -t closure <<<"$closure_output"
  for command in "$@"; do
    for closure_path in "${closure[@]}"; do
      [[ -x $closure_path/bin/$command ]] && continue 2
    done
    printf 'Runtime closure of %s lacks command: %s\n' "$root" "$command" >&2
    exit 1
  done
}

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
