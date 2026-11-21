#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tool="$repo_root/scripts/helix-deploy-isolated.sh"

bash "$tool" --help | grep -Fq 'Usage: helix-deploy-isolated'
bash "$tool" --help | grep -Fq 'Does not stash, reset'

# Regression: validation tools live in the staged worktree's pinned
# development shell, not necessarily on the deployed host's PATH.
if [[ $(grep -Fc "./scripts/dev-shell.sh --run './scripts/check.sh --quick'" "$tool") -ne 1 ]]; then
  printf 'Deployment must run its quick gate inside the pinned development shell\n' >&2
  exit 1
fi
if grep -Fqx './scripts/check.sh --quick' "$tool"; then
  printf 'Deployment directly invoked the quick gate outside the development shell\n' >&2
  exit 1
fi

if bash "$tool" --unexpected-argument >/dev/null 2>&1; then
  printf 'Invalid deploy argument unexpectedly succeeded\n' >&2
  exit 1
fi

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
git -c init.defaultBranch=main init -q "$test_dir/source"
git -C "$test_dir/source" remote add origin 'https://github.com/malicious/example.git'

# An untrusted origin must fail *before* any fetch, new worktree or sudo.
output=$(helix_checkout="$test_dir/source" bash "$tool" --check 2>&1) && {
  printf 'Untrusted origin unexpectedly accepted\n' >&2
  exit 1
}
grep -Fq 'Refusing unexpected source origin' <<<"$output"
[[ ! -e "$test_dir/source/.git/worktrees" ]]
printf 'Isolated deploy refusal and help tests passed.\n'
