#!/usr/bin/env bash

set -euo pipefail

case $# in
0) ;;
1)
  if [[ $1 == --help || $1 == -h ]]; then
    printf 'Usage: helix-update\n'
    printf 'Fast-forward to reviewed main, validate, build, diff, test-activate,\n'
    printf 'health-check and switch. Nixpkgs updates arrive as pull requests that\n'
    printf 'change nixpkgs.json (scripts/bump-nixpkgs.sh).\n'
    exit 0
  fi
  printf 'Usage: helix-update [--help]\n' >&2
  exit 2
  ;;
*)
  printf 'Usage: helix-update [--help]\n' >&2
  exit 2
  ;;
esac

# system/commands.nix prepends helix_checkout from config/helix.nix.
# shellcheck disable=SC2154
repo=${helix_checkout:?helix-update must be run as the installed command}
cd "$repo"

# Concurrent unattended updates are forbidden; the lock is owned by the
# invoking desktop user and does not depend on the NAS or root filesystem.
lock_dir=${XDG_RUNTIME_DIR:-"$HOME/.local/state/helix"}
mkdir -p -- "$lock_dir"
exec 9>"$lock_dir/helix-update.lock"
if ! flock -n 9; then
  printf 'Another helix-update is already running.\n' >&2
  exit 1
fi

# Never let repository-local Git configuration run commands here.
if [[ -n $(git -c core.fsmonitor=false -c core.hooksPath=/dev/null \
  status --porcelain --untracked-files=normal) ]]; then
  printf 'Refusing to update: %s has uncommitted or untracked files.\n' "$repo" >&2
  exit 1
fi

branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
if [[ $branch != main ]]; then
  printf 'Refusing to update: %s is on %s, not main.\n' "$repo" "${branch:-a detached HEAD}" >&2
  exit 1
fi

run_build() {
  if command -v nom >/dev/null 2>&1; then "$@" 2>&1 | nom; else "$@"; fi
}

temporary_directory=$(mktemp -d)
out_link="$temporary_directory/system"
trap 'rm -rf -- "$temporary_directory"' EXIT

# Nixpkgs is pinned in nixpkgs.json, so an update is a reviewed commit (see
# scripts/bump-nixpkgs.sh). Bring in reviewed main, never a local merge.
printf 'Fast-forwarding to the reviewed main branch...\n'
git -c core.fsmonitor=false -c core.hooksPath=/dev/null pull --ff-only
# The checkout, not the Nix store, provides this file at runtime.
# shellcheck source=/dev/null
source "$repo/scripts/release-environment.sh"
printf 'Running repository validation...\n'
./scripts/check.sh
printf 'Building candidate system...\n'
run_build nix-build --out-link "$out_link" '<nixpkgs/nixos>' -A system
candidate=$(readlink -f "$out_link")
printf 'Candidate package changes:\n'
nvd diff /run/current-system "$candidate"
previous=$(readlink -f /run/current-system)
previous_profile=$(readlink -f /nix/var/nix/profiles/system)
if [[ $previous != "$previous_profile" ]]; then
  printf 'Refusing ambiguous activation: running and selected system generations differ.\n' >&2
  printf 'Running:    %s\nPersistent: %s\n' "$previous" "$previous_profile" >&2
  exit 1
fi
if [[ ! -x $previous/bin/switch-to-configuration ]]; then
  printf 'Previous running generation is not a usable recovery target.\n' >&2
  exit 1
fi
printf 'Verifying the currently running generation before protecting it...\n'
"$previous/sw/bin/helix-health" --check

# The guarded helper protects the old closure from GC, test-activates the
# candidate, and rolls both the profile and runtime back on any error or
# interrupt. Its failure paths are exercised without root/activation in CI.
sudo -v
# shellcheck source=scripts/helix-update-transaction.sh
source "$repo/scripts/helix-update-transaction.sh"
helix_guarded_promote "$candidate" "$previous" "$previous_profile" \
  /nix/var/nix/gcroots/helix-known-good

profile=$(readlink -f /nix/var/nix/profiles/system)
generation=$(sudo nix-env --profile /nix/var/nix/profiles/system --list-generations |
  awk '$0 ~ /current/ { print $1 }')
printf 'Active system generation: %s (%s)\n' "$generation" "$profile"
printf 'Rollback: sudo nixos-rebuild switch --rollback\n'
