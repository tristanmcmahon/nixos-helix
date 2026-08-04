#!/usr/bin/env bash

qualification_hold=${HELIX_QUALIFICATION_DIR:-/var/lib/helix/release-qualification}
qualification_gcroot=${HELIX_ROLLBACK_GCROOT:-/nix/var/nix/gcroots/helix-pre-release-upgrade}
export qualification_hold qualification_gcroot

qualification_gcroot_plan() {
  local existing=${1:-}
  local running=$2
  if [[ -z $existing ]]; then
    printf 'create\n'
  elif [[ $existing == "$running" ]]; then
    printf 'reuse\n'
  else
    printf 'refuse\n'
  fi
}

qualification_hold_status() {
  if [[ -d $1 ]]; then printf 'active\n'; else printf 'inactive\n'; fi
}

qualification_workflow_plan() {
  printf '%s\n' \
    'hold=create-or-verify' \
    'rollback-gcroot=create-or-verify' \
    'validation=check,dry-build,build,dry-activate' \
    'activation=boot' \
    'running-system=unchanged' \
    'reboot=manual'
}
