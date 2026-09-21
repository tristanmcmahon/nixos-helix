#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

printf 'Checking local monitoring, history, and cooling controls...\n'
monitoring_dashboard=$system_closure/etc/helix/monitoring/dashboards/helix-overview.json
[[ -r $monitoring_dashboard ]]
python3 -m json.tool "$monitoring_dashboard" >/dev/null
grep -qF '"uid": "helix-overview"' "$monitoring_dashboard"
grep -qF '"from": "now-24h"' "$monitoring_dashboard"
[[ -x $system_closure/sw/bin/helix-monitor ]]
"$system_closure/sw/bin/helix-monitor" --help | grep -qF 'dashboard|fans|commission|inventory|restore|status'
[[ -x $system_closure/sw/bin/helix-fan-commission ]]
monitoring_launcher=$system_closure/sw/share/applications/helix-monitor.desktop
[[ -r $monitoring_launcher ]]
grep -qF 'Name=Helix Monitor' "$monitoring_launcher"
grep -qF 'helix-monitor dashboard' "$monitoring_launcher"
for monitoring_unit in \
  grafana \
  prometheus \
  prometheus-node-exporter \
  prometheus-nvidia-gpu-exporter \
  prometheus-smartctl-exporter \
  coolercontrold; do
  [[ -r $system_closure/etc/systemd/system/$monitoring_unit.service ]]
done
grep -qF -- '--web.listen-address=127.0.0.1:9090' \
  "$system_closure/etc/systemd/system/prometheus.service"
grep -qF -- '--storage.tsdb.retention.time=400d' \
  "$system_closure/etc/systemd/system/prometheus.service"
grep -qF -- '--web.listen-address 127.0.0.1:9100' \
  "$system_closure/etc/systemd/system/prometheus-node-exporter.service"
grep -qF -- '--web.listen-address 127.0.0.1:9835' \
  "$system_closure/etc/systemd/system/prometheus-nvidia-gpu-exporter.service"
grep -qF -- '--web.listen-address=127.0.0.1:9633' \
  "$system_closure/etc/systemd/system/prometheus-smartctl-exporter.service"
[[ -x $system_closure/sw/bin/grafana ]]
[[ -x $system_closure/sw/bin/coolercontrol ]]

