#!/usr/bin/env bash

set -Eeuo pipefail

repo=${HOME}/Projects/nixos-helix
expected_openclaw=2026.7.1-2
openclaw_rev=d3760a6f103642f11e24bc01ee9aec80a0153774
openclaw_sha256=1pfzr2c94x0f77qwpnb9gvvfvvsz59fgybpjwhb9fsrhlv1zli6y
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

printf '=== NORMALISE PINNED OPENCLAW INTEGRATION ===\n'
# Use the exact reviewed upstream overlay. Upstream intentionally constructs its
# package set from `prev`, not `final`; doing this ourselves against `final`
# creates a recursive fixed-point edge and can yield an invalid OpenClaw store
# path during strict NixOS evaluation.
cat > packages/openclaw.nix <<EOF
_:

let
  packageSource = builtins.fetchTarball {
    url = "https://github.com/openclaw/nix-openclaw/archive/${openclaw_rev}.tar.gz";
    sha256 = "${openclaw_sha256}";
  };
in
{
  nixpkgs.overlays = [
    (import "\${packageSource}/nix/overlay.nix" {
      openclawToolPkgs = { };
      qmdPkgs = { };
    })
  ];
}
EOF

nixfmt packages/openclaw.nix
git diff --check

# Use the repository's deterministic Nixpkgs selection.
# shellcheck source=/dev/null
source "$repo/scripts/release-environment.sh"

printf '\n=== BUILD CONFIGURED OPENCLAW PACKAGE ===\n'
# Build the exact package selected by Helix's NixOS configuration, not a
# separately imported approximation. This guarantees that the output realised
# here is the same store path the strict invariant evaluator later sees.
openclaw_output=$(nix-build --no-out-link -E "
  let
    system = import <nixpkgs/nixos> {
      configuration = ${repo}/configuration.nix;
    };
  in
  system.pkgs.openclaw
")
printf 'Configured OpenClaw package: %s\n' "$openclaw_output"
[[ -x $openclaw_output/bin/openclaw ]] || {
  printf 'Configured OpenClaw output is not realised correctly.\n' >&2
  exit 1
}
focused_openclaw_version=$($openclaw_output/bin/openclaw --version 2>/dev/null || true)
printf 'Configured OpenClaw version: %s\n' "$focused_openclaw_version"
grep -q "$expected_openclaw" <<<"$focused_openclaw_version" || {
  printf 'Configured OpenClaw is not %s.\n' "$expected_openclaw" >&2
  exit 1
}

printf '\n=== FULL REPOSITORY GATE ===\n'
./scripts/dev-shell.sh --run './scripts/check.sh'

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
