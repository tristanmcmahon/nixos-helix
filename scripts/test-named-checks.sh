#!/usr/bin/env bash
# Tests both a Boolean failure and a thrown Nix assertion without a host build.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

passed=$(nix-instantiate --eval --strict -E \
  '(import ./tests/lib/named-checks.nix) [ { name = "passes"; value = true; } ]')
[[ $passed == true ]] || {
  printf 'Named-check positive fixture failed: %s\n' "$passed" >&2
  exit 1
}

if error=$(nix-instantiate --eval --strict -E \
  '(import ./tests/lib/named-checks.nix) [
     { name = "boolean-failure"; value = false; }
     { name = "assertion-failure"; value = (assert false; true); }
     { name = "passing-check"; value = true; }
   ]' 2>&1); then
  printf 'Named-check negative fixture unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -qF 'boolean-failure, assertion-failure' <<<"$error" || {
  printf 'Missing names from failed modules:\n%s\n' "$error" >&2
  exit 1
}
printf 'Named invariant reporting fixtures passed.\n'
