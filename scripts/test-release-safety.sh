#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-qualification-lib.sh"
running=/nix/store/source-system

[[ $(qualification_gcroot_plan '' "$running") == create ]]
[[ $(qualification_gcroot_plan "$running" "$running") == reuse ]]
[[ $(qualification_gcroot_plan /nix/store/other "$running") == refuse ]]
temporary_hold=$(mktemp -d)
trap 'rmdir -- "$temporary_hold"' EXIT
[[ $(qualification_hold_status "$temporary_hold") == active ]]
rmdir "$temporary_hold"
trap - EXIT
[[ $(qualification_hold_status "$temporary_hold") == inactive ]]
plan=$(qualification_workflow_plan)
script_plan=$("$repo_root/scripts/prepare-release-boot.sh" --plan)
[[ $script_plan == "$plan" ]]
grep -qxF 'activation=boot' <<<"$plan"
if grep -Eq 'activation=(test|switch)' <<<"$plan"; then exit 1; fi
if grep -Eq 'rebuild\.sh (test|switch)' "$repo_root/scripts/prepare-release-boot.sh"; then exit 1; fi
grep -qF "./scripts/dev-shell.sh --run './scripts/check.sh'" \
  "$repo_root/scripts/prepare-release-boot.sh"
if grep -qxF './scripts/check.sh' "$repo_root/scripts/prepare-release-boot.sh"; then exit 1; fi
grep -qF "candidate=\$(nix-build --no-out-link '<nixpkgs/nixos>' -A system" \
  "$repo_root/scripts/prepare-release-boot.sh"
if grep -qF "sed -n 's/^Done. The new configuration is" \
  "$repo_root/scripts/prepare-release-boot.sh"; then exit 1; fi
grep -qF "sudo test -r \"/boot/loader/entries/nixos-generation-\$source_generation.conf\"" \
  "$repo_root/scripts/prepare-release-boot.sh"
grep -qF '(root access required to inspect /boot/loader/entries)' \
  "$repo_root/scripts/qualification-status.sh"
grep -qF 'sudo -n bootctl status' "$repo_root/scripts/reinstall-preflight.sh"
grep -qF 'sudo bootctl status' "$repo_root/scripts/post-reboot-release-check.sh"

grep -qF './scripts/rebuild.sh test' "$repo_root/scripts/install-helix.sh"
grep -qF './scripts/rebuild.sh switch' "$repo_root/scripts/install-helix.sh"
if grep -Eq '/mnt/infernalnexus/nas1|ls /mnt/infernalnexus' \
  "$repo_root/scripts/prepare-release-boot.sh" "$repo_root/scripts/post-reboot-release-check.sh"; then exit 1; fi
if rg -l 'nas-sustained-read-test\.sh --run' "$repo_root/scripts" \
  -g '!nas-sustained-read-test.sh' | grep -q .; then exit 1; fi

expected_release=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).nixosRelease")
fresh_state=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).freshStateVersion")
[[ $fresh_state == "$expected_release" ]]
printf 'Release safety planning tests passed.\n'
