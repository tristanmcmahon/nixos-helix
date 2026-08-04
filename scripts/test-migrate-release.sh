#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

current_plan=$("$repo_root/scripts/migrate-release.sh" --plan 26.05)
grep -qxF 'cleanup-action=stop' <<<"$current_plan"
grep -qxF 'channel-update=not-required' <<<"$current_plan"
grep -qxF 'cleanup-restore=sudo systemctl start helix-nix-cleanup.timer' <<<"$current_plan"

upgrade_plan=$("$repo_root/scripts/migrate-release.sh" --plan 25.11)
grep -qxF 'cleanup-action=stop' <<<"$upgrade_plan"
grep -qxF 'channel-update=required' <<<"$upgrade_plan"
grep -qxF 'cleanup-restore=sudo systemctl start helix-nix-cleanup.timer' <<<"$upgrade_plan"
