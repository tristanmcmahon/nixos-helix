#!/usr/bin/env bash

# Compare the versions that matter on Helix between the Nixpkgs pin at a Git
# revision (default HEAD) and the pin in the working tree, as a Markdown table.
# Used for Nixpkgs bump pull requests; it only reads.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${1:-} == --help || ${1:-} == -h || $# -gt 1 ]]; then
  printf 'Usage: %s [GIT-REVISION]\n' "${0##*/}"
  printf 'Compare key package versions between the pin at GIT-REVISION (default HEAD)\n'
  printf 'and the working-tree nixpkgs.json.\n'
  [[ $# -le 1 && ${1:-} == -* ]] && exit 0
  exit 2
fi
base=${1:-HEAD}

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT
git -C "$repo_root" show "$base:nixpkgs.json" > "$temporary_directory/base.json"

# The configuration takes the default kernel and Nixpkgs' stable NVIDIA driver
# for it, so these package-set attributes are what Helix runs.
versions() {
  nix-instantiate --eval --strict --json -E "
    let
      pin = builtins.fromJSON (builtins.readFile $1);
      pkgs = import (builtins.fetchTarball { inherit (pin) url sha256; }) {
        config.allowUnfree = true;
      };
      kernel = pkgs.linuxPackages;
    in {
      release = pin.release;
      kernel = kernel.kernel.version;
      nvidia = kernel.nvidiaPackages.stable.version;
      mesa = pkgs.mesa.version;
      plasma = pkgs.kdePackages.plasma-workspace.version;
      systemd = pkgs.systemd.version;
      firefox = pkgs.firefox.version;
      ollama = pkgs.ollama.version;
      node = pkgs.nodejs_22.version;
      sqlite = pkgs.sqlite.version;
      ghostty = pkgs.ghostty.version;
      # OpenClaw's Node is an override of this derivation, so it is rebuilt
      # from source exactly when this path changes, whatever the version says.
      nodeDerivation = builtins.unsafeDiscardStringContext pkgs.nodejs-slim_22.drvPath;
    }"
}

versions "$temporary_directory/base.json" > "$temporary_directory/base.versions"
versions "$repo_root/nixpkgs.json" > "$temporary_directory/new.versions"

python3 - "$temporary_directory/base.versions" "$temporary_directory/new.versions" <<'PYTHON'
import json
import sys

old, new = (json.load(open(path)) for path in sys.argv[1:3])
order = ["release", "kernel", "nvidia", "mesa", "plasma", "systemd",
         "firefox", "ollama", "node", "sqlite", "ghostty"]
print("| | Current | Proposed |")
print("|---|---|---|")
for key in order:
    marker = "" if old[key] == new[key] else " **changed**"
    print(f"| {key} | `{old[key]}` | `{new[key]}`{marker} |")
print()
if old["nodeDerivation"] != new["nodeDerivation"]:
    print("Node's inputs changed: Helix rebuilds OpenClaw's Node from source once.")
else:
    print("Node's inputs are unchanged: OpenClaw's Node is reused.")
if old["kernel"] != new["kernel"]:
    print()
    print("The kernel changed: the NVIDIA module is rebuilt locally and the new "
          "kernel needs a reboot.")
PYTHON
