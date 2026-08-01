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

printf 'Dry-building default configuration...\n'
./scripts/rebuild.sh dry-build

printf 'Dry-building local-LLM profile...\n'
./scripts/check-profile.sh local-llm
