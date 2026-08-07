#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
destination=$repo_root/storage/reinstall-targets.local.conf
[[ $# -eq 1 ]] || { printf 'Usage: %s INVENTORY_FILE\n' "$0" >&2; exit 2; }
inventory=$1
[[ -f $inventory && ! -L $inventory ]] || { printf 'Inventory must be a regular file.\n' >&2; exit 1; }
if ! grep -qx BEGIN_STORAGE_TSV "$inventory" || ! grep -qx END_STORAGE_TSV "$inventory"; then
  printf 'Inventory lacks the machine-readable section.\n' >&2; exit 1;
fi
[[ ! -e $destination ]] || { printf 'Refusing to overwrite %s\n' "$destination" >&2; exit 1; }
install -m 0600 "$repo_root/storage/reinstall-targets.example.conf" "$destination"
printf 'Created non-actionable local manifest: %s\n' "$destination"
printf 'Copy exact identities from %s, fill every blank, and review manually.\n' "$inventory"
