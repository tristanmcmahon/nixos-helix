#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

printf 'Building the complete default system closure...\n'
system_closure=$(nix-build --no-out-link '<nixpkgs/nixos>' -A system \
  -I "nixos-config=$repo_root/tests/build-configuration.nix")

# One evaluation of the canonical configuration supplies every other artifact.
printf 'Building inspected artifacts from the canonical configuration...\n'
artifacts=$(nix-build --no-out-link tests/artifacts.nix)
hyprland_config=$(readlink -f "$artifacts/hyprland.conf")
session_data=$(readlink -f "$artifacts/session-data")
# shellcheck disable=SC2034 # Used by the sourced applications checks.
onepassword_gui=$(readlink -f "$artifacts/1password-gui")
# shellcheck disable=SC2034 # Used by the sourced applications checks.
onepassword_cli=$(readlink -f "$artifacts/1password-cli")

printf 'Checking Helix health and update command surfaces...\n'
"$system_closure/sw/bin/helix-health" --help | grep -qF -- '--check'
grep -qF 'helix-health' "$system_closure/sw/bin/helix-update"
grep -qF 'nix-env --profile /nix/var/nix/profiles/system --set "$candidate"' \
  "$system_closure/sw/bin/helix-update"
# hamCade and emulation are left out of this disposable closure because their
# libretro MAME builds are expensive to compile; build-configuration.nix lists
# the overrides. Canonical hamCade enablement and launcher presence are
# asserted during the evaluation phase before this build.

printf 'Checking Vim and modern-bash in the built default system...\n'
./scripts/test-modern-bash.sh "$system_closure"

printf 'Verifying the repository-owned Hyprland baseline...\n'
"$system_closure/sw/bin/Hyprland" --verify-config --config "$hyprland_config"
polkit_agent=$(sed -n 's/^exec-once = \(.*polkit-kde-authentication-agent-1\)$/\1/p' "$hyprland_config")
[[ -x $polkit_agent ]]

printf 'Checking generated display-manager sessions...\n'

find "$session_data/share" -type f -name '*.desktop' -print
grep -Rqs '^Name=Plasma' "$session_data/share/wayland-sessions"
grep -Rqs '^Name=Hyprland' "$session_data/share/wayland-sessions"

