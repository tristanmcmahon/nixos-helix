#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-qualification-lib.sh"
# shellcheck disable=SC2154 # Assigned by release-qualification-lib.sh.
qualification_hold=${qualification_hold:?}
# shellcheck disable=SC2154 # Assigned by release-qualification-lib.sh.
qualification_gcroot=${qualification_gcroot:?}
expected_release=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).nixosRelease")
release_rollback=0
case ${1:-} in
"") ;;
--keep-rollback) ;;
--release-rollback) release_rollback=1 ;;
*) printf 'Usage: %s [--keep-rollback|--release-rollback]\n' "${0##*/}" >&2; exit 2 ;;
esac

[[ -d $qualification_hold ]]
[[ -f $qualification_hold/post-reboot-success ]]
running=$(readlink -f /run/current-system)
persistent=$(readlink -f /nix/var/nix/profiles/system)
[[ $running == "$persistent" ]]
[[ $(nixos-version | sed -E 's/^([0-9]+\.[0-9]+).*/\1/') == "$expected_release" ]]
saved_source=$(<"$qualification_hold/source-system-path")
[[ -e $saved_source ]]
[[ $(readlink -f "$qualification_gcroot") == "$saved_source" ]]
if systemctl is-active --quiet helix-nix-cleanup.timer; then exit 1; fi
[[ ! -e ${qualification_hold}.completed ]]

printf 'Type FINISH HELIX %s QUALIFICATION to continue: ' "$expected_release"
IFS= read -r confirmation
[[ $confirmation == "FINISH HELIX $expected_release QUALIFICATION" ]]
sudo mv "$qualification_hold" "${qualification_hold}.completed"
sudo systemctl start helix-nix-cleanup.timer
if ((release_rollback)); then
  sudo unlink "$qualification_gcroot"
else
  printf 'Rollback GC root retained: %s\n' "$qualification_gcroot"
fi
printf 'Qualification safeguards released. No garbage collection was run.\n'
