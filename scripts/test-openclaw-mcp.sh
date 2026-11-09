#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat >"$tmp/bin/openclaw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'token=%s\n' "$OPENCLAW_GATEWAY_TOKEN"
printf 'state=%s\n' "$OPENCLAW_STATE_DIR"
printf 'config=%s\n' "$OPENCLAW_CONFIG_PATH"
printf 'nix_mode=%s\n' "$OPENCLAW_NIX_MODE"
printf 'argv='
printf '<%s>' "$@"
printf '\n'
EOF
chmod +x "$tmp/bin/openclaw"

secret="$tmp/gateway.env"
printf '%s\n' 'OPENCLAW_GATEWAY_TOKEN="token with spaces"' >"$secret"

output=$(
  PATH="$tmp/bin:$PATH" \
    HELIX_OPENCLAW_SECRET_FILE="$secret" \
    HELIX_OPENCLAW_STATE_DIR="$tmp/state" \
    HELIX_OPENCLAW_CONFIG_PATH="$tmp/state/openclaw.json" \
    bash "$repo_root/scripts/helix-openclaw-mcp.sh"
)

grep -qFx 'token=token with spaces' <<<"$output"
grep -qFx "state=$tmp/state" <<<"$output"
grep -qFx "config=$tmp/state/openclaw.json" <<<"$output"
grep -qFx 'nix_mode=1' <<<"$output"
grep -qFx 'argv=<mcp><serve><--claude-channel-mode><off>' <<<"$output"
if grep -qF '<token with spaces>' <<<"$output"; then
  printf 'OpenClaw token leaked into MCP argv.\n' >&2
  exit 1
fi

printf '%s\n' 'OTHER=value' >"$secret"
if PATH="$tmp/bin:$PATH" \
  HELIX_OPENCLAW_SECRET_FILE="$secret" \
  HELIX_OPENCLAW_STATE_DIR="$tmp/state" \
  HELIX_OPENCLAW_CONFIG_PATH="$tmp/state/openclaw.json" \
  bash "$repo_root/scripts/helix-openclaw-mcp.sh" >/dev/null 2>&1; then
  printf 'OpenClaw MCP adapter accepted a missing Gateway token.\n' >&2
  exit 1
fi

printf 'OpenClaw MCP adapter preserves secret boundaries.\n'
