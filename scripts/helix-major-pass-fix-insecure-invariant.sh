#!/usr/bin/env bash

set -Eeuo pipefail

repo=${HOME}/Projects/nixos-helix
cd "$repo"

branch=$(git branch --show-current)
case $branch in
upgrade/helix-major-pass-*) ;;
*)
  printf 'Refusing outside a helix major-pass branch: %s\n' "$branch" >&2
  exit 1
  ;;
esac

printf '=== FIX OPTIONAL INSECURE-PACKAGE INVARIANT ===\n'
python3 - <<'PY'
from pathlib import Path

path = Path("tests/system-invariants.nix")
text = path.read_text(encoding="utf-8")
old = 'assert config.nixpkgs.config.permittedInsecurePackages == [ ];'
new = 'assert (config.nixpkgs.config.permittedInsecurePackages or [ ]) == [ ];'

if new in text:
    print("Invariant already handles an absent permittedInsecurePackages attribute.")
elif old in text:
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("Updated invariant: missing permittedInsecurePackages now means no exceptions.")
else:
    raise SystemExit("Expected permittedInsecurePackages invariant not found; refusing ambiguous edit")
PY

nixfmt tests/system-invariants.nix
git diff --check -- tests/system-invariants.nix

printf '\n=== RESUME MAJOR PASS ===\n'
git fetch origin main
bash <(git show origin/main:scripts/helix-major-pass-resume.sh)
