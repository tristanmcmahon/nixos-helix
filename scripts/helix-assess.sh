#!/usr/bin/env bash
# Non-interactive workstation metrics, Nix closure timings and GPU evidence.
# No NixOS activation, driver change, or Steam process manipulation.
set -euo pipefail
umask 077

usage() {
  cat <<'USAGE'
Usage: scripts/helix-assess.sh [--full|--quick|--profile-only]
  --full          Baseline plus full Nix release gate (default)
  --quick         Baseline plus quick validation
  --profile-only  Baseline only; no builds

Logs remain private under ~/.local/state/helix/assessments/.
Real Xid 109 qualification requires a repeatable, attended Proton game session.
USAGE
}
mode=full
case ${1:-} in
  "") ;;
  --full) ;;
  --quick) mode=quick ;;
  --profile-only) mode=profile ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$repo_root"
state_root=${XDG_STATE_HOME:-$HOME/.local/state}/helix/assessments
mkdir -p -m 0700 -- "$state_root"
revision=$(git rev-parse --short=12 HEAD)
stamp=$(date -u '+%Y%m%dT%H%M%SZ')
result_dir=$state_root/$stamp-$revision
mkdir -m 0700 -- "$result_dir"
summary=$result_dir/SUMMARY.txt
printf 'Helix assessment: %s\nGit revision: %s\nMode: %s\n' \
  "$stamp" "$(git rev-parse HEAD)" "$mode" | tee "$summary"
printf 'NixOS system closure: %s\n' "$(readlink -f /run/current-system)" | tee -a "$summary"

failures=0
probe() {
  local label=$1 started elapsed result
  shift
  started=$SECONDS
  if "$@" > "$result_dir/$label.log" 2>&1; then
    result=PASS
  else
    result=FAIL
    failures=$((failures + 1))
  fi
  elapsed=$((SECONDS - started))
  printf 'PROBE %-25s %-11s %5ss  %s\n' "$label" "$result" "$elapsed" \
    "$result_dir/$label.log" | tee -a "$summary"
}
optional_probe() {
  local label=$1 started elapsed result
  shift
  started=$SECONDS
  if "$@" > "$result_dir/$label.log" 2>&1; then
    result=PASS
  else
    result=UNAVAILABLE
  fi
  elapsed=$((SECONDS - started))
  printf 'PROBE %-25s %-11s %5ss  %s\n' "$label" "$result" "$elapsed" \
    "$result_dir/$label.log" | tee -a "$summary"
}

probe health helix-health --check
# These benignly append to helix-benchmark's existing per-user JSONL history.
optional_probe profile helix-benchmark profile
optional_probe system helix-benchmark system
optional_probe compute helix-benchmark compute --compute-duration 15
optional_probe llm helix-benchmark llm --llm-tokens 200

# Queries are read-only. The full gate below builds actual missing store paths.
optional_probe closure-size timeout 60 nix --extra-experimental-features nix-command \
  path-info -S /run/current-system
if [[ $mode == full ]]; then
  optional_probe closure-eval nix-instantiate '<nixpkgs/nixos>' -A system \
    -I "nixos-config=$repo_root/tests/build-configuration.nix"
  optional_probe closure-plan nix-build --dry-run --no-out-link '<nixpkgs/nixos>' \
    -A system -I "nixos-config=$repo_root/tests/build-configuration.nix"
fi

optional_probe nvidia-smi nvidia-smi \
  --query-gpu=name,driver_version,power.draw,utilization.gpu,memory.used \
  --format=csv,noheader,nounits
optional_probe nvidia-xids journalctl -k -b --no-pager \
  -g 'NVRM: Xid|CTX SWITCH TIMEOUT'
# Never use helix-benchmark gpu here: that command may launch and terminate a
# running Cyberpunk game. vkmark only is safe for a non-interactive profile.
if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && command -v vkmark >/dev/null 2>&1; then
  optional_probe gpu-vkmark timeout 300 vkmark --present-mode immediate
else
  printf 'PROBE gpu-vkmark                SKIPPED (no GUI session or vkmark)\n' \
    | tee -a "$summary"
fi

case $mode in
  full) probe full-gate ./scripts/dev-shell.sh --run './scripts/check.sh --full' ;;
  quick) probe quick-gate ./scripts/dev-shell.sh --run './scripts/check.sh --quick' ;;
esac

if [[ -f $result_dir/full-gate.log ]]; then
  grep '^HELIX_TIMING ' "$result_dir/full-gate.log" > "$result_dir/CLOSURE_TIMINGS.txt" || true
elif [[ -f $result_dir/quick-gate.log ]]; then
  grep '^HELIX_TIMING ' "$result_dir/quick-gate.log" > "$result_dir/CLOSURE_TIMINGS.txt" || true
fi

printf 'RESULT_DIR=%s\nRequired probe failures: %s\n' "$result_dir" "$failures" | tee -a "$summary"
((failures == 0))
