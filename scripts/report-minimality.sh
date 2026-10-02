#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-environment.sh"
cd "$repo_root"

printf 'Release: %s (state version %s)\n' \
  "$HELIX_SELECTED_RELEASE" \
  "$(nix-instantiate --eval --raw -E '(import ./release.nix).stateVersion')"

printf 'Top-level system packages:\n'
nix-instantiate --eval --strict -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    names = map (package: package.pname or package.name or "")
      system.config.environment.systemPackages;
  in builtins.sort builtins.lessThan names
'

printf 'Unique top-level package count: '
nix-instantiate --eval --strict -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    lib = system.pkgs.lib;
    names = map (package: package.pname or package.name or "")
      system.config.environment.systemPackages;
  in builtins.length (lib.unique names)
'

system_closure=$(nix-build --no-out-link '<nixpkgs/nixos>' -A system \
  -I "nixos-config=$repo_root/configuration.nix")
printf 'Built system closure: %s\n' "$system_closure"
nix path-info -Sh "$system_closure" 2>/dev/null || nix-store -q --size "$system_closure"

# Derived from the evaluated configuration so the report cannot drift. Every
# other Helix service binds to loopback, which tests/invariants enforce.
printf 'Firewall-open ports (TCP / UDP):\n'
nix-instantiate --eval --strict -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    firewall = system.config.networking.firewall;
  in { tcp = firewall.allowedTCPPorts; udp = firewall.allowedUDPPorts; }
'
printf 'Custom pins:\n'
grep -nE 'version = |rev = |tag = |Commit:|url = ' \
  packages/openclaw.nix packages/zen-browser.nix packages/gridplayer.nix \
  packages/hamllm.nix shell/modern-bash.nix vendor/hamcade/dependencies.nix
