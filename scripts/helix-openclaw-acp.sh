#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf '%s\n' \
    'Usage: helix-openclaw-acp [OPENCLAW-ACP-ARGS...]' \
    'Run OpenClaw ACP against the Helix loopback Gateway using its existing runtime state and token.'
  exit 0
fi

: "${HELIX_OPENCLAW_SECRET_FILE:?missing Helix OpenClaw secret path}"
: "${HELIX_OPENCLAW_STATE_DIR:?missing Helix OpenClaw state path}"
: "${HELIX_OPENCLAW_CONFIG_PATH:?missing Helix OpenClaw config path}"

if [[ ! -r $HELIX_OPENCLAW_SECRET_FILE ]]; then
  printf 'OpenClaw Gateway secret is not readable: %s\n' "$HELIX_OPENCLAW_SECRET_FILE" >&2
  exit 1
fi

token_line=$(grep -m1 -E '^[[:space:]]*OPENCLAW_GATEWAY_TOKEN=' "$HELIX_OPENCLAW_SECRET_FILE" || true)
if [[ -z $token_line ]]; then
  printf 'OPENCLAW_GATEWAY_TOKEN is missing from %s\n' "$HELIX_OPENCLAW_SECRET_FILE" >&2
  exit 1
fi

token=${token_line#*=}
token=${token%$'\r'}

# Accept the normal quoted or unquoted systemd EnvironmentFile forms without
# evaluating the secret file as shell code.
if [[ $token == \"*\" && $token == *\" ]]; then
  token=${token:1:${#token}-2}
elif [[ $token == \'*\' && $token == *\' ]]; then
  token=${token:1:${#token}-2}
fi

if [[ -z $token ]]; then
  printf 'OPENCLAW_GATEWAY_TOKEN is empty in %s\n' "$HELIX_OPENCLAW_SECRET_FILE" >&2
  exit 1
fi

export OPENCLAW_GATEWAY_TOKEN="$token"
export OPENCLAW_STATE_DIR="$HELIX_OPENCLAW_STATE_DIR"
export OPENCLAW_CONFIG_PATH="$HELIX_OPENCLAW_CONFIG_PATH"
export OPENCLAW_HIDE_BANNER=1
export OPENCLAW_SUPPRESS_NOTES=1

exec openclaw acp "$@"
