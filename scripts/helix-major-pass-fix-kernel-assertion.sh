#!/usr/bin/env bash

set -Eeuo pipefail

repo=${HOME}/Projects/nixos-helix
cd "$repo"

branch=$(git branch --show-current)
case $branch in
upgrade/helix-major-pass-*) ;;
*)
  printf 'Refusing to repair outside a helix major-pass branch: %s\n' "$branch" >&2
  exit 1
  ;;
esac

printf '=== REPAIR KERNEL FAMILY ASSERTION ===\n'
python3 <<'PY'
from pathlib import Path

path = Path("scripts/helix-major-pass.sh")
text = path.read_text(encoding="utf-8")
old = '''NEW_KERNEL="$(readlink -f "$NEW_SYSTEM/kernel")"
printf 'Candidate kernel: %s\\n' "$NEW_KERNEL"
grep -Eq '/linux-6\\.18\\.' <<<"$NEW_KERNEL" \\
  || die "candidate kernel is not in the 6.18 LTS family"
'''
new = '''NEW_KERNEL="$(readlink -f "$NEW_SYSTEM/kernel")"
printf 'Candidate kernel: %s\\n' "$NEW_KERNEL"
KERNEL_STORE_NAME="$(basename "$(dirname "$NEW_KERNEL")")"
grep -Eq '(^|-)linux-6\\.18\\.' <<<"$KERNEL_STORE_NAME" \\
  || die "candidate kernel is not in the 6.18 LTS family"
'''
if old in text:
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("Fixed the versioned major-pass kernel assertion.")
elif "KERNEL_STORE_NAME=" in text and "linux-6\\.18\\." in text:
    print("Versioned major-pass kernel assertion is already fixed.")
else:
    raise SystemExit("Could not find the reviewed kernel assertion; refusing an ambiguous rewrite.")
PY

bash -n scripts/helix-major-pass.sh
git diff --check

printf '\n=== RESUME MAJOR PASS ===\n'
git fetch origin main
bash <(git show origin/main:scripts/helix-major-pass-resume.sh)
