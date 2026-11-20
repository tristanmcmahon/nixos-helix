#!/usr/bin/env bash
# Promote reviewed origin/main without requiring the user's active checkout to
# be clean. Git worktree plumbing is intentionally distinct from NixOS activation.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: helix-deploy-isolated --check|--execute

--check    fetch reviewed origin/main into a temporary clean worktree and
           run the quick validation gate, without a NixOS activation
--execute  additionally build/diff/test-activate/health-check and switch,
           with an attempted rollback on any failed activation step

Does not stash, reset, checkout, commit, clean or modify the active worktree.
EOF
}
case ${1:-} in
  --check|--execute)
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    mode=$1
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

# The Nix-packaged command supplies helix_checkout. When bootstrapping from a
# temporary worktree, use the established canonical path without assuming that
# checkout is clean or on main.
source_checkout=${helix_checkout:-"$HOME/Projects/nixos-helix"}
[[ -d $source_checkout/.git || -f $source_checkout/.git ]] || {
  printf 'Missing canonical Git checkout: %s\n' "$source_checkout" >&2
  exit 1
}
source_checkout=$(cd -- "$source_checkout" && pwd -P)
git_safe() {
  git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$source_checkout" "$@"
}

remote=$(git_safe remote get-url origin)
case "$remote" in
  https://github.com/tristanmcmahon/nixos-helix|\
  https://github.com/tristanmcmahon/nixos-helix.git|\
  git@github.com:tristanmcmahon/nixos-helix.git|\
  ssh://git@github.com/tristanmcmahon/nixos-helix.git)
    ;;
  *)
    printf 'Refusing unexpected source origin: %s\n' "$remote" >&2
    exit 1
    ;;
esac

state_root="$HOME/.local/state/helix/isolated-deploy"
install -d -m 0700 -- "$state_root"
exec 9>"$state_root/deploy.lock"
if ! flock -n 9; then
  printf 'Another isolated Helix deployment is running.\n' >&2
  exit 1
fi

scratch=
staged=
registered=0
rollback_needed=0
previous=
previous_profile=
on_exit() {
  local code=$?
  trap - EXIT INT TERM
  if ((rollback_needed && code != 0)); then
    printf '\nDeployment failed; attempting restoration of the prior boot profile and runtime.\n' >&2
    if ! sudo -n nix-env --profile /nix/var/nix/profiles/system --set "$previous_profile"; then
      printf 'CRITICAL: unable to restore previous system profile; use the boot menu.\n' >&2
    fi
    if ! sudo -n "$previous/bin/switch-to-configuration" switch; then
      printf 'CRITICAL: unable to restore previous runtime; use the boot menu.\n' >&2
    fi
  fi
  # Only the path created by this invocation may be removed. Never force
  # removal: a concurrent actor who modified it needs their work preserved.
  if ((registered)); then
    if ! git_safe worktree remove -- "$staged"; then
      printf 'Temporary Git worktree retained for inspection: %s\n' "$staged" >&2
      exit "$code"
    fi
  fi
  if [[ -n $scratch ]]; then
    rm -f -- "$scratch/system"
    rmdir -- "$scratch" 2>/dev/null || true
  fi
  exit "$code"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Fetching reviewed main (active checkout state is not inspected or changed)...\n'
git_safe fetch --no-tags origin refs/heads/main:refs/remotes/origin/main
commit=$(git_safe rev-parse --verify 'refs/remotes/origin/main^{commit}')
printf 'Reviewed candidate: %s\n' "$commit"

scratch=$(mktemp -d "$state_root/stage.XXXXXXXX")
staged="$scratch/repo"
git_safe worktree add --detach -- "$staged" "$commit"
registered=1

# Nothing evaluated below reads the active checkout as the source of NixOS
# modules. The only input to the candidate closure is this detached worktree
# and its own immutable Nixpkgs pin.
cd -- "$staged"
if [[ -n $(git -c core.fsmonitor=false -c core.hooksPath=/dev/null status --porcelain) ]]; then
  printf 'Refusing unexpectedly dirty deployment worktree.\n' >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$staged/scripts/release-environment.sh"
printf 'Validating reviewed candidate %s...\n' "$commit"
./scripts/check.sh --quick

if [[ $mode == --check ]]; then
  printf 'Isolated candidate validation passed. No NixOS activation performed.\n'
  exit 0
fi

printf 'Building production candidate from isolated worktree...\n'
if command -v nom >/dev/null 2>&1; then
  nix-build --out-link "$scratch/system" '<nixpkgs/nixos>' -A system 2>&1 | nom
else
  nix-build --out-link "$scratch/system" '<nixpkgs/nixos>' -A system
fi
candidate=$(readlink -e "$scratch/system")
[[ -x $candidate/bin/switch-to-configuration && -x $candidate/sw/bin/helix-health ]] || {
  printf 'Candidate is missing its activation or runtime-health tool.\n' >&2
  exit 1
}
printf 'Package and closure differences:\n'
nvd diff /run/current-system "$candidate"

previous=$(readlink -e /run/current-system)
previous_profile=$(readlink -e /nix/var/nix/profiles/system)
if [[ $previous != "$previous_profile" ]]; then
  printf 'Refusing activation: currently running and selected boot generations differ.\n' >&2
  printf 'running: %s\nselected: %s\n' "$previous" "$previous_profile" >&2
  exit 1
fi
[[ -x $previous/bin/switch-to-configuration && -x $previous/sw/bin/helix-health ]] || {
  printf 'Refusing activation: previous generation has no safe recovery commands.\n' >&2
  exit 1
}
printf 'Checking the running known-good system before promotion...\n'
"$previous/sw/bin/helix-health" --check

# Store a persistent, GC-protected fallback before mutating the running system.
# A Nix GC root is not in itself proof of a visible bootloader menu entry.
sudo -v
fallback_root=/nix/var/nix/gcroots/helix-known-good
fallback_tmp="$fallback_root.new.$$"
sudo -n install -d -m 0755 /nix/var/nix/gcroots
sudo -n ln -s -- "$previous" "$fallback_tmp"
if ! sudo -n mv -Tf -- "$fallback_tmp" "$fallback_root"; then
  sudo -n rm -f -- "$fallback_tmp" || true
  printf 'Refusing activation without a protected known-good store closure.\n' >&2
  exit 1
fi

# From this point, any trap-observable activation failure restores the prior
# profile *and* runtime, not merely the currently running configuration.
# Power loss or a failed rollback still requires a manual boot-menu recovery.
rollback_needed=1
printf 'Test-activating isolated candidate...\n'
sudo -n "$candidate/bin/switch-to-configuration" test
printf 'Checking candidate runtime health...\n'
"$candidate/sw/bin/helix-health" --check
printf 'Registering candidate as a system generation...\n'
sudo -n nix-env --profile /nix/var/nix/profiles/system --set "$candidate"
printf 'Selecting candidate as boot generation...\n'
sudo -n "$candidate/bin/switch-to-configuration" switch
rollback_needed=0

printf 'Successful isolated deployment: %s\n' "$commit"
printf 'Current system: %s\n' "$(readlink -f /nix/var/nix/profiles/system)"
printf 'Protected previous generation: %s\n' "$previous"
