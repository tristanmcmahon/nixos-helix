#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

printf 'Checking the Netdata stream and cooling controls...\n'
[[ -x $system_closure/sw/bin/helix-monitor ]]
# Check each subcommand separately so adding one does not break the gate.
monitor_usage=$("$system_closure/sw/bin/helix-monitor" --help)
for monitor_subcommand in netdata fans commission inventory restore status; do
  [[ $monitor_usage =~ (\[|\|)$monitor_subcommand(\||\]) ]]
done
[[ -x $system_closure/sw/bin/helix-fan-commission ]]
[[ -x $system_closure/sw/bin/coolercontrol ]]
monitoring_launcher=$system_closure/sw/share/applications/helix-monitor.desktop
[[ -r $monitoring_launcher ]]
grep -qF 'Name=Helix Monitor' "$monitoring_launcher"
grep -qF 'helix-monitor netdata' "$monitoring_launcher"
for monitoring_unit in netdata coolercontrold; do
  [[ -r $system_closure/etc/systemd/system/$monitoring_unit.service ]]
done
# The local history stack was retired in favour of the Infernalnexus parent.
for retired_unit in grafana prometheus prometheus-node-exporter \
  prometheus-nvidia-gpu-exporter prometheus-smartctl-exporter; do
  [[ ! -e $system_closure/etc/systemd/system/$retired_unit.service ]]
done
