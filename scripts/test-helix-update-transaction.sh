#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d --tmpdir=/tmp)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/previous/bin" "$work/candidate/bin" "$work/candidate/sw/bin" "$work/gcroots"
cat > "$work/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
"$@"
MOCK
cat > "$work/bin/nix-env" <<'MOCK'
#!/usr/bin/env bash
printf 'profile %s\n' "$*" >> "$HELIX_TEST_LOG"
if [[ ${HELIX_TEST_FAIL_PROFILE:-0} == 1 && $* == *candidate* ]]; then exit 1; fi
MOCK
cat > "$work/previous/bin/switch-to-configuration" <<'MOCK'
#!/usr/bin/env bash
printf 'previous %s\n' "$1" >> "$HELIX_TEST_LOG"
MOCK
cat > "$work/candidate/bin/switch-to-configuration" <<'MOCK'
#!/usr/bin/env bash
printf 'candidate %s\n' "$1" >> "$HELIX_TEST_LOG"
case "$1" in
test) [[ ${HELIX_TEST_FAIL_TEST:-0} != 1 ]] ;;
switch) [[ ${HELIX_TEST_FAIL_SWITCH:-0} != 1 ]] ;;
esac
MOCK
cat > "$work/candidate/sw/bin/helix-health" <<'MOCK'
#!/usr/bin/env bash
printf 'health %s\n' "$1" >> "$HELIX_TEST_LOG"
[[ ${HELIX_TEST_FAIL_HEALTH:-0} != 1 ]]
MOCK
chmod +x "$work/bin/"* "$work/previous/bin/"* "$work/candidate/bin/"* "$work/candidate/sw/bin/"*
export PATH="$work/bin:$PATH"
export HELIX_TEST_LOG="$work/log"
source_script="$repo_root/scripts/helix-update-transaction.sh"
candidate="$work/candidate"
previous="$work/previous"
root="$work/gcroots/known-good"

run_case() {
  : > "$HELIX_TEST_LOG"
  ( set -euo pipefail; source "$source_script"; helix_guarded_promote "$candidate" "$previous" "$previous" "$root" )
}
for scenario in TEST HEALTH PROFILE SWITCH; do
  flag="HELIX_TEST_FAIL_$scenario"
  export "$flag=1"
  if run_case >/dev/null 2>&1; then
    printf 'Fault scenario %s unexpectedly succeeded\n' "$scenario" >&2
    exit 1
  fi
  unset "$flag"
  grep -Fxq 'previous switch' "$HELIX_TEST_LOG" || {
    printf 'Fault scenario %s never restored the prior system\n' "$scenario" >&2
    exit 1
  }
  grep -Fq "profile --profile /nix/var/nix/profiles/system --set $previous" "$HELIX_TEST_LOG"
  [[ $(readlink "$root") == "$previous" ]]
done
run_case >/dev/null
grep -Fxq 'candidate test' "$HELIX_TEST_LOG"
grep -Fxq 'health --check' "$HELIX_TEST_LOG"
grep -Fxq 'candidate switch' "$HELIX_TEST_LOG"
if grep -Fxq 'previous switch' "$HELIX_TEST_LOG"; then
  echo 'Successful promotion performed rollback' >&2
  exit 1
fi
[[ $(readlink "$root") == "$previous" ]]
echo 'Guarded activation failure-injection tests passed.'
