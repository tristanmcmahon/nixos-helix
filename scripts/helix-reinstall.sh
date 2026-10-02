#!/usr/bin/env bash

# One entry point for the disaster-recovery and planned-reinstall tooling in
# scripts/reinstall. See docs/reinstall.md for the order and the manual gates.
set -euo pipefail

reinstall_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/reinstall" && pwd)

usage() {
  printf 'Usage: %s COMMAND [ARGS...]\n\n' "${0##*/}"
  printf '  preflight        read-only readiness check before a reinstall\n'
  printf '  backup           verified one-shot archive to the NAS\n'
  printf '  check-storage    read-only disk layout check from the installer\n'
  printf '  restore          restore the archive onto the new installation\n'
  printf '  postflight       verify the restored system\n'
  printf '  verify-hardware  compare hardware against the recorded inventory\n'
  printf '  inventory        record the current hardware inventory\n'
}

command=${1:-}
case $command in
preflight | backup | check-storage | restore | postflight | verify-hardware | inventory)
  shift
  exec "$reinstall_dir/$command.sh" "$@"
  ;;
-h | --help)
  usage
  ;;
*)
  usage >&2
  exit 2
  ;;
esac
