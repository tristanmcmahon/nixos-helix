#!/usr/bin/env bash
set -euo pipefail

repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
expected_repo="/home/tristan/Projects/nixos-helix"
report_root="/mnt/games_nvme/emulation/reports"
discovery_report="$report_root/openclaw-mame-discovery.md"
review_report="$report_root/openclaw-retroarch-review.md"
secret_file="/home/tristan/.config/openclaw/gateway.env"

if [[ "$repo" != "$expected_repo" ]]; then
  printf 'Run this from %s (found %s).\n' "$expected_repo" "${repo:-no git repository}" >&2
  exit 1
fi

for command_name in git systemctl openclaw codex nix-instantiate; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command is missing: %s\n' "$command_name" >&2
    exit 1
  fi
done

if [[ -n "$(git -C "$repo" status --porcelain)" ]]; then
  printf 'Refusing to start with a dirty repository. Commit/stash current work first.\n' >&2
  git -C "$repo" status --short >&2
  exit 1
fi

mkdir -p "$report_root"

if ! systemctl --user is-active --quiet openclaw-gateway.service; then
  printf 'Starting OpenClaw gateway...\n'
  systemctl --user start openclaw-gateway.service
fi

service_environment="$(systemctl --user show openclaw-gateway.service --property=Environment --value)"
openclaw_config_path="$(printf '%s\n' "$service_environment" | tr ' ' '\n' | sed -n 's/^OPENCLAW_CONFIG_PATH=//p' | tail -n1)"
openclaw_state_dir="$(printf '%s\n' "$service_environment" | tr ' ' '\n' | sed -n 's/^OPENCLAW_STATE_DIR=//p' | tail -n1)"

if [[ -z "$openclaw_config_path" || -z "$openclaw_state_dir" ]]; then
  printf 'Could not resolve OpenClaw config/state paths from the running gateway.\n' >&2
  exit 1
fi

export OPENCLAW_CONFIG_PATH="$openclaw_config_path"
export OPENCLAW_STATE_DIR="$openclaw_state_dir"

if [[ -r "$secret_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$secret_file"
  set +a
fi

printf '\n== Claw: live Helix discovery ==\n'
openclaw agent \
  --session-key agent:main:helix-emulation-discovery \
  --message-file "$repo/docs/openclaw-emulation.md" \
  --json \
  > "$report_root/openclaw-discovery-turn.json"

if [[ ! -s "$discovery_report" ]]; then
  printf 'OpenClaw did not produce the required discovery report: %s\n' "$discovery_report" >&2
  exit 1
fi

printf '\n== Codex: implement RetroArch-first Helix ==\n'
{
  cat "$repo/docs/codex-emulation.md"
  printf '\n\n# Live OpenClaw discovery evidence\n\n'
  cat "$discovery_report"
} | (
  cd "$repo"
  codex exec --sandbox workspace-write --ephemeral
)

if [[ -z "$(git -C "$repo" status --porcelain)" ]]; then
  printf 'Codex produced no repository changes.\n' >&2
  exit 1
fi

printf '\n== Claw: review Codex against live evidence ==\n'
openclaw agent \
  --session-key agent:main:helix-emulation-review \
  --message-file "$repo/docs/openclaw-retroarch-review.md" \
  --json \
  > "$report_root/openclaw-review-turn.json"

if [[ ! -s "$review_report" ]]; then
  printf 'OpenClaw did not produce the required review report: %s\n' "$review_report" >&2
  exit 1
fi

printf '\n== Codex: final review fixes ==\n'
{
  cat "$repo/docs/codex-emulation.md"
  printf '\n\n# OpenClaw engineering review\n\n'
  cat "$review_report"
  printf '\n\nAddress every concrete item under FIX. Do not widen scope.\n'
} | (
  cd "$repo"
  codex exec --sandbox workspace-write --ephemeral
)

printf '\n== Fast repository gates (no system switch, no full closure build) ==\n'
git -C "$repo" diff --check
(
  cd "$repo"
  nix-instantiate --parse profiles/emulation.nix >/dev/null
  nix-instantiate --eval --strict tests/emulation-disabled.nix >/dev/null
  nix-instantiate '<nixpkgs/nixos>' -A system \
    -I "nixos-config=$repo/tests/emulation-configuration.nix" >/dev/null
)

printf '\nAI emulation pass complete. No rebuild or NAS mutation was performed.\n'
printf 'Review with: git diff --stat && git diff\n'
printf 'Then activate with: ./scripts/rebuild.sh switch\n'
printf 'After activation, run: helix-retroarch-status\n'
