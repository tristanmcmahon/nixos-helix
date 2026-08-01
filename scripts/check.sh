#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

printf 'Checking Nix formatting...\n'
temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT

while IFS= read -r nix_file; do
  temporary_file="$temporary_directory/${nix_file//\//_}"
  cp -- "$nix_file" "$temporary_file"
  nixfmt "$temporary_file"
  if ! cmp -s -- "$nix_file" "$temporary_file"; then
    printf 'Formatting required: %s\n' "$nix_file" >&2
    diff -u -- "$nix_file" "$temporary_file" || true
    exit 1
  fi
done < <(find . -name '*.nix' -type f ! -name hardware-configuration.nix -print | sort)

printf 'Checking shell syntax...\n'
bash -n scripts/*.sh

printf 'Running ShellCheck...\n'
shellcheck scripts/*.sh

printf 'Checking Git whitespace...\n'
git diff --check

printf 'Testing generation-cleanup planning...\n'
cleanup_program=$(nix-build --no-out-link -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    matches = builtins.filter
      (package: (package.name or "") == "helix-nix-cleanup")
      system.config.environment.systemPackages;
  in
  builtins.head matches
')
./scripts/test-cleanup-plan.sh "$cleanup_program/bin/helix-nix-cleanup"

printf 'Evaluating editor and desktop invariants...\n'
nix-instantiate --eval --strict -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    config = system.config;
    packageNames = map
      (package: package.pname or package.name or "")
      config.environment.systemPackages;
  in
  assert config.services.desktopManager.plasma6.enable;
  assert config.services.displayManager.sddm.enable;
  assert config.programs.hyprland.enable;
  assert config.programs.hyprland.withUWSM;
  assert config.environment.variables.EDITOR == "vim";
  assert config.environment.variables.VISUAL == "vim";
  assert builtins.any (name: builtins.match "vim.*" name != null) packageNames;
  true
'

printf 'Building the default closure for command and session inspection...\n'
system_closure=$(nix-build --no-out-link '<nixpkgs/nixos>' -A system \
  -I "nixos-config=$repo_root/configuration.nix")
./scripts/test-modern-bash.sh "$system_closure"

printf 'Checking generated display-manager sessions...\n'
session_data=$(nix-build --no-out-link -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.services.displayManager.sessionData.desktops
')
find "$session_data/share" -type f -name '*.desktop' -print
grep -Rqs '^Name=Plasma' "$session_data/share/wayland-sessions"
grep -Rqs '^Name=Hyprland' "$session_data/share/wayland-sessions"

printf 'Dry-building default configuration...\n'
./scripts/rebuild.sh dry-build

printf 'Dry-building local-LLM profile...\n'
./scripts/check-profile.sh local-llm
