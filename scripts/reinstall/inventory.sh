#!/usr/bin/env bash
# Produce a read-only hardware report on stdout. Redirect it to a file outside
# this repository because it can contain UUIDs, MAC addresses, and device names.

set -u
set -o pipefail

section() {
  printf '\n\n===== %s =====\n' "$1"
}

run_command() {
  local command_name=$1
  shift

  printf '\n$ %s' "$command_name"
  printf ' %q' "$@"
  printf '\n'

  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" "$@" 2>&1 ||
      printf '[command exited with status %s]\n' "$?"
  else
    printf '[not installed]\n'
  fi
}

printf 'Helix hardware inventory\n'
printf 'Collected: %s\n' "$(date --iso-8601=seconds)"
printf 'Kernel: %s\n' "$(uname -srmo)"
printf 'This script only reads system state; it does not refresh metadata or apply updates.\n'

section 'Operating system and machine'
run_command hostnamectl
run_command lscpu
run_command inxi --system --machine --cpu --graphics --audio --network --drives --usb --sensors --no-host

section 'PCI devices, drivers, and chipset'
run_command lspci -nnk

section 'USB devices and controller topology'
run_command lsusb
run_command lsusb -t

section 'Block devices, filesystems, and mounts'
run_command lsblk -e 7 -o NAME,PATH,TYPE,SIZE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS,MODEL,TRAN
run_command findmnt --real --output SOURCE,TARGET,FSTYPE,OPTIONS
run_command nvme list
run_command smartctl --scan-open

section 'Network interfaces and drivers'
run_command ip -brief link
run_command nmcli device status
run_command iw dev

section 'Graphics driver and DRM outputs'
run_command nvidia-smi
run_command nvidia-smi --query-gpu=name,pci.bus_id,driver_version,display_active,display_mode --format=csv
run_command glxinfo -B
run_command vulkaninfo --summary

found_drm_output=false
for status_file in /sys/class/drm/card*-*/status; do
  if [[ -r "$status_file" ]]; then
    found_drm_output=true
    connector=${status_file%/status}
    printf '\n%s: %s\n' "${connector##*/}" "$(<"$status_file")"
    if [[ -r "$connector/modes" ]]; then
      sed 's/^/  mode: /' "$connector/modes"
    fi
  fi
done
if [[ "$found_drm_output" == false ]]; then
  printf '\n[no readable DRM connector status files]\n'
fi

section 'Audio, microphones, and cameras'
run_command wpctl status
run_command v4l2-ctl --list-devices

section 'Bluetooth and radio state'
run_command bluetoothctl list
run_command rfkill list

section 'Sensors and firmware devices'
run_command sensors
run_command fwupdmgr get-devices

section 'Kernel modules and recent hardware errors'
run_command lsmod
run_command journalctl -b -p warning..alert --no-pager

section 'Listening sockets'
run_command ss -lntup

printf '\nInventory complete. Review identifiers before sharing or committing this output.\n'
