#!/usr/bin/env bash

# Point nixpkgs.json at the newest NixOS release of the pinned series (or an
# explicit release name). It only edits the file: review the diff, run
# ./scripts/check.sh and ./scripts/rebuild.sh dry-build, then open a PR.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
series=$(nix-instantiate --eval --raw -E "(import $repo_root/release.nix).nixosRelease")

if [[ $# -gt 1 ]]; then
  printf 'Usage: %s [nixos-%s.N.REV]\n' "${0##*/}" "$series" >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  base="https://releases.nixos.org/nixos/$series/$1"
else
  base=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://channels.nixos.org/nixos-$series")
fi
release=${base##*/}
[[ $release == "nixos-$series."* ]] || {
  printf 'Unexpected release %s for series %s\n' "$release" "$series" >&2
  exit 1
}

revision=$(curl -fsS "$base/git-revision")
url="$base/nixexprs.tar.xz"
sha256=$(nix-prefetch-url --unpack --name source "$url")

cat > "$repo_root/nixpkgs.json" <<JSON
{
  "release": "$release",
  "revision": "$revision",
  "url": "$url",
  "sha256": "$sha256"
}
JSON
printf 'Pinned %s (%s).\n' "$release" "$revision"
