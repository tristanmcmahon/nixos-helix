#!/usr/bin/env bash

set -Eeuo pipefail

repo=${HOME}/Projects/nixos-helix
expected_openclaw=2026.7.1-2
cd "$repo"

branch=$(git branch --show-current)
case $branch in
upgrade/helix-major-pass-*) ;;
*)
  printf 'Refusing to resume outside a helix major-pass branch: %s\n' "$branch" >&2
  exit 1
  ;;
esac

if [[ -z $(git status --porcelain) ]]; then
  printf 'Refusing to resume: working tree is clean; there is no interrupted major pass to continue.\n' >&2
  exit 1
fi

sudo -v

printf '=== FIX CURRENT LINT BLOCKERS ===\n'
# Keep Codex away from this script's stdin. This matters when the helper itself
# is executed from process substitution or another non-interactive source.
if ! codex exec 'Work only in /home/tristan/Projects/nixos-helix. Fix the two current Statix findings without changing semantics: (1) profiles/gaming.nix has repeated programs.* keys; consolidate them into one programs attribute set. (2) packages/openclaw.nix has a Statix "assignment instead of inherit from" warning around the openclaw binding; rewrite it idiomatically with inherit while preserving the exact pinned first-party OpenClaw package selection. Run nixfmt on touched Nix files and statix check on those files. Do not make any unrelated changes, do not commit, do not activate, do not run GC.' </dev/null; then
  printf 'WARNING: Codex could not complete its sandbox-local validation; continuing to the authoritative host-side repository gate.\n' >&2
fi

git diff --check

printf '\n=== FULL REPOSITORY GATE ===\n'
./scripts/dev-shell.sh --run './scripts/check.sh'

# Use the repository's deterministic Nixpkgs selection.
# shellcheck source=/dev/null
source "$repo/scripts/release-environment.sh"

printf '\n=== BUILD CANDIDATE ===\n'
candidate=$(nix-build --no-out-link '<nixpkgs/nixos>' -A system \
  -I "nixos-config=$repo/configuration.nix")
printf 'Candidate: %s\n' "$candidate"

printf '\n=== SYSTEM DIFF ===\n'
if [[ -x $candidate/sw/bin/nvd ]]; then
  "$candidate/sw/bin/nvd" diff /run/current-system "$candidate" || true
else
  printf 'WARNING: candidate has no nvd executable.\n' >&2
fi

printf '\n=== STATIC ASSERTIONS ===\n'
kernel=$(readlink -f "$candidate/kernel")
printf 'Kernel closure: %s\n' "$kernel"
grep -Eq '/linux-6\.18\.' <<<"$kernel" || {
  printf 'Candidate kernel escaped the 6.18 LTS family.\n' >&2
  exit 1
}

openclaw_version=$($candidate/sw/bin/openclaw --version 2>/dev/null || true)
printf 'OpenClaw: %s\n' "$openclaw_version"
grep -q "$expected_openclaw" <<<"$openclaw_version" || {
  printf 'Candidate OpenClaw is not %s.\n' "$expected_openclaw" >&2
  exit 1
}

for executable in helix-health helix-update helix-theme protonplus protontricks goverlay gamescope nom nvd; do
  [[ -x $candidate/sw/bin/$executable ]] || {
    printf 'Candidate missing executable: %s\n' "$executable" >&2
    exit 1
  }
done

"$candidate/sw/bin/helix-theme" list | tee /tmp/helix-theme-list.txt
for theme in fern petrol plum oxide amber rosewood hotdog; do
  grep -q "$theme" /tmp/helix-theme-list.txt || {
    printf 'Theme list missing %s.\n' "$theme" >&2
    exit 1
  }
done
grep -qi 'regrettably available' /tmp/helix-theme-list.txt || {
  printf 'Hot Dog Stand is insufficiently regrettable.\n' >&2
  exit 1
}

printf '\n=== TEST ACTIVATE ===\n'
./scripts/rebuild.sh test

printf '\n=== RUNTIME ASSERTIONS ===\n'
systemctl is-active --quiet systemd-oomd.service || {
  systemctl status systemd-oomd.service --no-pager -l || true
  exit 1
}

if ! swapon --show=NAME --noheadings 2>/dev/null | grep -q zram; then
  zramctl || true
  swapon --show || true
  printf 'zram swap is not active.\n' >&2
  exit 1
fi

systemctl --user is-active --quiet openclaw-gateway.service || {
  systemctl --user status openclaw-gateway.service --no-pager -l || true
  journalctl --user -u openclaw-gateway.service -b -n 100 --no-pager || true
  exit 1
}

runtime_openclaw=$(/run/current-system/sw/bin/openclaw --version 2>/dev/null || true)
printf 'Runtime OpenClaw: %s\n' "$runtime_openclaw"
grep -q "$expected_openclaw" <<<"$runtime_openclaw" || exit 1

nvidia-smi >/dev/null
/run/current-system/sw/bin/helix-health

printf '\n=== SWITCH ===\n'
./scripts/rebuild.sh switch

printf '\n=== COMMIT VALIDATED CHANGE ===\n'
git add -A
git diff --cached --check
if ! git diff --cached --quiet; then
  git commit -m 'Modernize Helix workstation configuration'
fi

printf '\n=== APPLY 14-DAY GC ===\n'
sudo nix-collect-garbage --delete-older-than 14d

printf '\n=== FINAL GENERATIONS ===\n'
sudo nix-env -p /nix/var/nix/profiles/system --list-generations

printf '\n=== COMPLETE ===\n'
printf 'Branch: %s\n' "$branch"
printf 'Commit: %s\n' "$(git rev-parse HEAD)"
printf 'System: %s\n' "$(readlink -f /nix/var/nix/profiles/system)"
printf 'Kernel: %s\n' "$(uname -r)"
printf 'OpenClaw: %s\n' "$(/run/current-system/sw/bin/openclaw --version 2>/dev/null || true)"
printf 'Rollback: sudo nixos-rebuild --rollback switch\n'
printf 'Publish branch: git push -u origin %s\n' "$branch"
