#!/usr/bin/env bash

set -uo pipefail

heading() { printf '\n%s\n' "$1"; }
status_word() {
  if systemctl is-active --quiet "$1" 2>/dev/null; then printf 'up'; else printf 'DOWN'; fi
}

printf 'Helix health — %s\n' "$(date --iso-8601=seconds)"
printf 'NixOS: %s | kernel: %s\n' "$(nixos-version 2>/dev/null || printf unknown)" "$(uname -r)"
profile=$(readlink -f /nix/var/nix/profiles/system 2>/dev/null || printf unknown)
generation=$(nix-env --profile /nix/var/nix/profiles/system --list-generations 2>/dev/null |
  awk '$0 ~ /current/ { print $1 }' || true)
generation=${generation:-unknown}
printf 'System: generation %s (%s)\n' "$generation" "$profile"

heading 'Graphics'
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,memory.used,memory.total \
    --format=csv,noheader 2>/dev/null || printf 'WARNING: NVIDIA driver is present but GPU status failed.\n'
else
  printf 'WARNING: nvidia-smi is unavailable.\n'
fi

heading 'Memory and storage'
free -h | sed -n '1,2p'
swapon --show --output=NAME,TYPE,SIZE,USED,PRIO 2>/dev/null || true
df -h -l --output=target,size,used,avail,pcent 2>/dev/null | awk '!seen[$0]++'

heading 'Services'
failed=$(systemctl --failed --no-legend --plain 2>/dev/null || true)
failed_count=$(grep -c . <<<"$failed" || true)
printf 'Failed system units: %s\n' "$failed_count"
[[ -z $failed ]] || printf '%s\n' "$failed"
if systemctl --user show-environment >/dev/null 2>&1; then
  user_failed=$(systemctl --user --failed --no-legend --plain 2>/dev/null || true)
  printf 'Failed user units: %s\n' "$(grep -c . <<<"$user_failed" || true)"
  [[ -z $user_failed ]] || printf '%s\n' "$user_failed"
else
  printf 'Failed user units: unavailable outside a user session\n'
fi
printf 'OpenClaw %s | gateway: %s\n' "$(openclaw --version 2>/dev/null || printf unknown)" \
  "$(systemctl --user is-active openclaw-gateway.service 2>/dev/null || printf unavailable)"
for service in grafana prometheus prometheus-node-exporter prometheus-nvidia-gpu-exporter \
  prometheus-smartctl-exporter coolercontrold; do
  printf '%-39s %s\n' "$service" "$(status_word "$service.service")"
done

heading 'NixOS channel'
channel=/nix/var/nix/profiles/per-user/root/channels/nixos
if [[ -e $channel ]]; then
  target=$(readlink -f "$channel" 2>/dev/null || printf unknown)
  printf 'root nixos: %s\n' "$target"
  if [[ -e $target ]]; then
    printf 'selected source age: %s days\n' "$(( ($(date +%s) - $(stat -c %Y "$target")) / 86400 ))"
  fi
else
  printf 'WARNING: root nixos channel is not installed.\n'
fi
