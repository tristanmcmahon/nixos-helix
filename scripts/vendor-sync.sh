#!/usr/bin/env bash

# Replace one vendored snapshot with an upstream commit's files and record the
# commit in vendor/sources.json. See vendor/README.md.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest=$repo_root/vendor/sources.json

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s NAME COMMIT\n' "${0##*/}" >&2
  exit 2
fi
name=$1
commit=$2
[[ $commit =~ ^[0-9a-f]{40}$ ]] || {
  printf 'COMMIT must be a full 40-character hash.\n' >&2
  exit 2
}

repository=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["repository"])' "$manifest" "$name") || {
  printf 'Unknown vendored snapshot: %s\n' "$name" >&2
  exit 2
}
mapfile -t paths < <(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))[sys.argv[2]]["paths"]))' "$manifest" "$name")

checkout=$(mktemp -d)
trap 'rm -rf -- "$checkout"' EXIT
git clone --quiet --filter=blob:none --no-checkout "https://github.com/$repository" "$checkout"
git -C "$checkout" -c advice.detachedHead=false checkout --quiet "$commit"

destination=$repo_root/vendor/$name
for path in "${paths[@]}"; do
  [[ -e $checkout/$path ]] || {
    printf '%s is missing at %s\n' "$path" "$commit" >&2
    exit 1
  }
  rm -rf -- "${destination:?}/$path"
  mkdir -p -- "$(dirname -- "$destination/$path")"
  cp -R -- "$checkout/$path" "$destination/$path"
done

python3 - "$manifest" "$name" "$commit" <<'PY'
import json, sys
path, name, commit = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    sources = json.load(handle)
sources[name]["commit"] = commit
with open(path, "w", encoding="utf-8") as handle:
    json.dump(sources, handle, indent=2)
    handle.write("\n")
PY
printf 'vendor/%s now matches %s@%s.\n' "$name" "$repository" "$commit"
