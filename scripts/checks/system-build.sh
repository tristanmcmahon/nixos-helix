#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

printf 'Evaluating release, storage, desktop, and security invariants...\n'
nix-instantiate --eval --strict tests/system-invariants.nix
nix-instantiate --eval --strict tests/monitoring-disabled.nix

printf 'Building the complete default system closure...\n'
system_closure=$(nix-build --no-out-link '<nixpkgs/nixos>' -A system \
  -I "nixos-config=$repo_root/tests/build-configuration.nix")

printf 'Checking Vim and modern-bash in the built default system...\n'
./scripts/test-modern-bash.sh "$system_closure"

printf 'Verifying the repository-owned Hyprland baseline...\n'
hyprland_config=$(nix-build --no-out-link -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.environment.etc."hypr/helix.conf".source
')
"$system_closure/sw/bin/Hyprland" --verify-config --config "$hyprland_config"
polkit_agent=$(sed -n 's/^exec-once = \(.*polkit-kde-authentication-agent-1\)$/\1/p' "$hyprland_config")
[[ -x $polkit_agent ]]

printf 'Checking generated display-manager sessions...\n'
configured_display_manager=$(nix-instantiate --eval --raw -E '
  let
    system = import <nixpkgs/nixos> {
      configuration = ./configuration.nix;
    };
  in
  system.config.services.displayManager.generic.execCmd
')
[[ -n $configured_display_manager ]]
grep -qi 'sddm' <<<"$configured_display_manager"

session_data=$(nix-build --no-out-link -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.services.displayManager.sessionData.desktops
')
find "$session_data/share" -type f -name '*.desktop' -print
grep -Rqs '^Name=Plasma' "$session_data/share/wayland-sessions"
grep -Rqs '^Name=Hyprland' "$session_data/share/wayland-sessions"

