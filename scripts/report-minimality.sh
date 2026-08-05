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

printf 'Intentional listeners/services:\n'
printf '%s\n' 'sshd: TCP 22' 'NetworkManager' 'Ollama: loopback TCP 11434'
printf 'Custom pins:\n'
rg -n 'version =|rev =|Commit:' packages/zen-browser.nix packages/gridplayer.nix shell/modern-bash.nix
