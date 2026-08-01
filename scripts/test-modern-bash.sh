#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s SYSTEM_CLOSURE\n' "${0##*/}" >&2
  exit 2
fi

system_closure=$1
system_path="$system_closure/sw/bin"
system_bash="$system_path/bash"
system_bashrc="$system_closure/etc/bashrc"
temporary_home=$(mktemp -d)
trap 'rm -rf -- "$temporary_home"' EXIT
test_bashrc="$temporary_home/bashrc"

[[ -x $system_bash ]] || {
  printf 'Missing Bash in evaluated closure: %s\n' "$system_bash" >&2
  exit 1
}
[[ -r $system_bashrc ]] || {
  printf 'Missing evaluated Bash startup file: %s\n' "$system_bashrc" >&2
  exit 1
}

# `bash -ic` without a terminal has no PS1 while its rcfile is being read, but
# NixOS intentionally gates interactive initialization on PS1. Model the state
# present in a normal terminal without reading or writing the user's real home.
printf 'PS1=test\n__ETC_PROFILE_DONE=1\nunset __ETC_BASHRC_SOURCED NOSYSBASHRC\nsource %q\n' \
  "$system_bashrc" >"$test_bashrc"

HOME=$temporary_home PATH=$system_path "$system_bash" --noprofile --norc -c true
HOME=$temporary_home PATH=$system_path "$system_bash" --rcfile "$test_bashrc" -ic true
HOME=$temporary_home PATH=$system_path "$system_bash" --rcfile "$test_bashrc" -ic 'type vi'
HOME=$temporary_home PATH=$system_path "$system_bash" --rcfile "$test_bashrc" -ic 'type vim'
# The expansion is intentionally deferred to the isolated child shell.
# shellcheck disable=SC2016
HOME=$temporary_home PATH=$system_path "$system_bash" --rcfile "$test_bashrc" -ic \
  'type modern-bash; type modern_bash::bootstrap::shutdown; [[ ${MODERN_BASH_INITIALIZED:-0} == 1 ]]'

"$system_path/vi" --version >/dev/null
"$system_path/vim" --version >/dev/null
"$system_path/modern-bash" version >/dev/null
HOME=$temporary_home "$system_path/modern-bash" doctor --plain >/dev/null

for lifecycle_command in install uninstall; do
  lifecycle_output="$temporary_home/$lifecycle_command.output"
  if HOME=$temporary_home "$system_path/modern-bash" "$lifecycle_command" >"$lifecycle_output" 2>&1; then
    printf 'modern-bash %s unexpectedly succeeded.\n' "$lifecycle_command" >&2
    exit 1
  fi
  grep -Fx 'modern-bash is managed by the Helix NixOS configuration.' "$lifecycle_output" >/dev/null
  grep -Fx 'Edit shell/modern-bash.nix and rebuild the system instead.' "$lifecycle_output" >/dev/null
done
printf 'Vim/vi and modern-bash passed isolated closure tests.\n'
