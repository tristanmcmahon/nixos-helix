#!/usr/bin/env bash
# Isolated NVIDIA 620.70.06 experiment for Helix; does not modify production Nix modules.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/helix/nvidia-620.70.06
candidate_config=$state_dir/configuration.nix
baseline_file=$state_dir/baseline-store-path
revision_file=$state_dir/source-revision
version=620.70.06
label=helix-nvidia620-test

usage() {
  cat <<'USAGE'
Usage: scripts/helix-nvidia620-test.sh {prepare|build|stage|status|rollback}
  prepare   Prefetch NVIDIA 620.70.06 and create a separate NixOS test config
  build     Build, but do not register or activate, the test system
  stage     Register a new labeled NixOS generation for NEXT boot only
  status    Show test state, current GPU driver and registered generations
  rollback  Restore the recorded pre-test generation for NEXT boot only

Only 'stage' or 'rollback' touches the system profile or bootloader.
Do not use helix-update while a test generation is staged; it targets main.
USAGE
}

require_candidate() {
  [[ -r $candidate_config && -r $revision_file ]] || {
    printf 'No prepared test configuration. Run prepare first.\n' >&2
    exit 1
  }
  local expected actual
  expected=$(<"$revision_file")
  actual=$(git -C "$repo_root" rev-parse HEAD)
  if [[ $expected != "$actual" ]]; then
    printf 'Repo changed since prepare (%s -> %s); rerun prepare before build/stage.\n' \
      "$expected" "$actual" >&2
    exit 1
  fi
}

# Nix base32 sha256. nix-prefetch-url prints the hash to stdout and progress to stderr.
prefetch() {
  local desc=$1 url=$2 mode=$3 fallback=${4:-} value
  printf 'Prefetching %s...\n' "$desc" >&2
  if [[ $mode == unpack ]]; then
    if ! value=$(nix-prefetch-url --unpack "$url"); then
      [[ -n $fallback ]] || return 1
      printf 'Trying official NVIDIA source archive for %s...\n' "$desc" >&2
      value=$(nix-prefetch-url --unpack "$fallback")
    fi
  else
    value=$(nix-prefetch-url "$url")
  fi
  if [[ ! $value =~ ^[0-9a-z]{52}$ ]]; then
    printf 'Bad SHA-256 from nix-prefetch-url for %s: %s\n' "$desc" "$value" >&2
    exit 1
  fi
  printf '%s\n' "$value"
}

prepare() {
  source "$repo_root/scripts/release-environment.sh"
  if [[ $(uname -m) != x86_64 ]]; then
    printf 'This experiment is for Helix x86_64 only.\n' >&2; exit 1
  fi
  mkdir -p "$state_dir"
  local installer open settings persistenced revision
  installer=$(prefetch "NVIDIA Linux x86_64 driver" \
    "https://us.download.nvidia.com/XFree86/Linux-x86_64/$version/NVIDIA-Linux-x86_64-$version.run" flat)
  open=$(prefetch 'NVIDIA open kernel modules' \
    "https://github.com/NVIDIA/open-gpu-kernel-modules/archive/$version.tar.gz" unpack)
  # kernel-modules.nix passes this through fetchFromGitHub's generic `hash`
  # attribute (the other three go through its algorithm-named `sha256`
  # attribute instead), which requires an explicit SRI type prefix; bare
  # nix32 output from nix-prefetch-url fails evaluation there with "hash
  # does not include a type, nor is the type otherwise known from context."
  open=$(nix --extra-experimental-features nix-command hash convert \
    --hash-algo sha256 --to sri "$open")
  settings=$(prefetch 'NVIDIA settings' \
    "https://github.com/NVIDIA/nvidia-settings/archive/$version.tar.gz" unpack \
    "https://download.nvidia.com/XFree86/nvidia-settings/nvidia-settings-$version.tar.bz2")
  persistenced=$(prefetch 'NVIDIA persistenced' \
    "https://github.com/NVIDIA/nvidia-persistenced/archive/$version.tar.gz" unpack \
    "https://download.nvidia.com/XFree86/nvidia-persistenced/nvidia-persistenced-$version.tar.bz2")
  revision=$(git -C "$repo_root" rev-parse HEAD)

  # Generate a standalone top-level module. This imports the same pinned Helix
  # configuration, changing only the NVIDIA driver and its boot label.
  cat > "$candidate_config" <<NIX
{ config, ... }:
{
  imports = [ $repo_root/configuration.nix ];
  system.nixos.label = "$label";
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
    version = "$version";
    sha256_64bit = "$installer";
    openSha256 = "$open";
    settingsSha256 = "$settings";
    persistencedSha256 = "$persistenced";
  };
}
NIX
  printf '%s\n' "$revision" > "$revision_file"
  printf 'Prepared: %s\nPinned Nixpkgs: %s\nGit revision: %s\n' \
    "$candidate_config" "$HELIX_SELECTED_RELEASE" "$revision"
}

build() {
  require_candidate
  source "$repo_root/scripts/release-environment.sh"
  # Use a named store-link in private state, not a stray result symlink in the repo.
  nix-build '<nixpkgs/nixos>' -A system \
    -I "nixos-config=$candidate_config" -o "$state_dir/candidate"
  printf 'Built candidate: %s\n' "$(readlink -f "$state_dir/candidate")"
  if command -v nvd >/dev/null 2>&1; then
    nvd diff /run/current-system "$state_dir/candidate"
  fi
}

stage() {
  require_candidate
  [[ -e $state_dir/candidate ]] || {
    printf 'Build the candidate first: %s build\n' "$0" >&2; exit 1
  }
  source "$repo_root/scripts/release-environment.sh"
  local baseline
  baseline=$(readlink -f /nix/var/nix/profiles/system)
  [[ -x $baseline/bin/switch-to-configuration ]] || {
    printf 'Cannot verify current baseline system closure.\n' >&2; exit 1
  }
  [[ ! -e $baseline_file ]] || {
    printf 'A baseline is already recorded at %s. Roll back or inspect it first.\n' "$baseline_file" >&2
    exit 1
  }
  sudo -v
  # Keep the original Nix store closure alive despite Helix's 14-day GC.
  nix-store -r --add-root "$state_dir/baseline-gc-root" "$baseline" >/dev/null
  printf '%s\n' "$baseline" > "$baseline_file"
  printf 'Baseline preserved: %s\n' "$baseline"
  printf 'Staging %s for the NEXT reboot. Running driver remains unchanged.\n' "$label"
  sudo -n env NIX_PATH="$NIX_PATH" nixos-rebuild boot \
    -I "nixos-config=$candidate_config"
  printf '\nStaged. Reboot to test, or run rollback to cancel the next boot.\n'
  sudo -n nix-env --profile /nix/var/nix/profiles/system --list-generations | tail -n 8
}

status() {
  printf 'Experiment: NVIDIA %s (%s)\n' "$version" "$label"
  [[ ! -r $revision_file ]] || printf 'Prepared at Git revision: %s\n' "$(<"$revision_file")"
  [[ ! -r $baseline_file ]] || printf 'Preserved baseline: %s\n' "$(<"$baseline_file")"
  [[ ! -e $state_dir/candidate ]] || printf 'Candidate store path: %s\n' "$(readlink -f "$state_dir/candidate")"
  printf 'Running system: %s\n' "$(readlink -f /run/current-system)"
  nvidia-smi --query-gpu=name,driver_version --format=csv,noheader || true
  sudo -v
  sudo -n nix-env --profile /nix/var/nix/profiles/system --list-generations | tail -n 12
  printf 'Recent Xids:\n'
  journalctl -k -b --no-pager | grep -E 'NVRM: Xid|Xid \(' | tail -n 12 || true
}

rollback() {
  [[ -r $baseline_file ]] || {
    printf 'No recorded baseline. Nothing to roll back.\n' >&2; exit 1
  }
  local baseline
  baseline=$(<"$baseline_file")
  [[ -x $baseline/bin/switch-to-configuration ]] || {
    printf 'Baseline closure no longer exists: %s\n' "$baseline" >&2; exit 1
  }
  sudo -v
  sudo -n nix-env --profile /nix/var/nix/profiles/system --set "$baseline"
  sudo -n "$baseline/bin/switch-to-configuration" boot
  printf 'Restored pre-test generation as NEXT boot default: %s\n' "$baseline"
  printf 'Running kernel and GPU driver will not change until reboot.\n'
}

if [[ $# != 1 ]]; then usage >&2; exit 2; fi
case $1 in
  prepare) prepare ;;
  build) build ;;
  stage) stage ;;
  status) status ;;
  rollback) rollback ;;
  -h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
