#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_base=$(mktemp -d --tmpdir=/tmp)
trap 'rm -rf -- "$test_base"' EXIT
mkdir -p "$test_base/bin" "$test_base/state"
cat > "$test_base/bin/systemctl" <<'MOCK'
#!/usr/bin/env bash
if [[ ${HELIX_MOCK_TIMER_INACTIVE:-0} == 1 ]]; then exit 1; fi
[[ ${1:-} == is-active && ${2:-} == --quiet ]] || exit 2
case ${3:-} in
  restic-backups-helix.timer|hamology-backup.timer) exit 0 ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$test_base/bin/systemctl"
export PATH="$test_base/bin:$PATH"
export HELIX_RECOVERY_TEST_MODE=1
export HELIX_RECOVERY_TEST_ROOT="$test_base/state"
receipt="$repo_root/scripts/helix-recovery-receipt.sh"
health="$repo_root/scripts/helix-recovery.sh"

if bash "$health" --check >/dev/null 2>&1; then
  echo 'Accepted missing receipts' >&2
  exit 1
fi
bash "$receipt" restic
bash "$receipt" hamology
bash "$health" --check | grep -Fq 'Helix recovery readiness: PASS'

old=$(( $(date -u +%s) - 172801 ))
printf '%s\n' "$old" > "$test_base/state/last-success-restic"
if bash "$health" --check >/dev/null 2>&1; then
  echo 'Accepted stale receipt' >&2
  exit 1
fi
bash "$receipt" restic
printf '%s\n' malformed > "$test_base/state/last-success-restic"
if bash "$health" --check >/dev/null 2>&1; then
  echo 'Accepted malformed receipt' >&2
  exit 1
fi
bash "$receipt" restic
if HELIX_MOCK_TIMER_INACTIVE=1 bash "$health" --check >/dev/null 2>&1; then
  echo 'Accepted stopped timer' >&2
  exit 1
fi
rm -f "$test_base/state/last-success-hamology"
if bash "$health" --check >/dev/null 2>&1; then
  echo 'Accepted missing hamology receipt' >&2
  exit 1
fi
if bash "$receipt" unexpected >/dev/null 2>&1; then
  echo 'Accepted unknown backup name' >&2
  exit 1
fi
echo 'Recovery freshness tests passed.'
