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
install -d -m 0700 -- "$state_root"
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
# journalctl -g exits nonzero when no entries match, which is not a probe error.
# Read the boot journal and distinguish a clean match-free boot from failure.
read_nvidia_xids() {
  journalctl -k -b --no-pager |
    awk '/NVRM: Xid|CTX SWITCH TIMEOUT/ { found = 1; print }
      END { if (!found) print "No matching GPU faults in accessible boot journal." }'
}
optional_probe nvidia-xids read_nvidia_xids
# Never use helix-benchmark gpu here: that command may launch and terminate a
# running Cyberpunk game. vkmark only is safe for a non-interactive profile.
if [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
  printf 'PROBE gpu-vkmark                SKIPPED (no graphical session)\n' \
    | tee -a "$summary"
elif ! command -v vkmark >/dev/null 2>&1; then
  printf 'PROBE gpu-vkmark                SKIPPED (vkmark unavailable)\n' \
    | tee -a "$summary"
else
  optional_probe gpu-vkmark timeout 300 vkmark --present-mode immediate
fi

# Record timing markers directly in a separate log, independent of Nix output.
timing_file=$result_dir/CLOSURE_TIMINGS.txt
case $mode in
  full)
    probe full-gate env HELIX_TIMING_FILE="$timing_file" \
      ./scripts/dev-shell.sh --run './scripts/check.sh --full'
    gate_log=$result_dir/full-gate.log
    ;;
  quick)
    probe quick-gate env HELIX_TIMING_FILE="$timing_file" \
      ./scripts/dev-shell.sh --run './scripts/check.sh --quick'
    gate_log=$result_dir/quick-gate.log
    ;;
  *) gate_log= ;;
esac

# Support historic output if the instrumented gate is not in this checkout.
if [[ -n $gate_log && ! -s $timing_file ]]; then
  grep -aoE 'HELIX_TIMING (phase|subphase)=[^[:cntrl:]]+' \
    "$gate_log" > "$timing_file" || true
fi

printf 'RESULT_DIR=%s\nRequired probe failures: %s\n' "$result_dir" "$failures" | tee -a "$summary"
((failures == 0))
