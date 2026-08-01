# Hardware validation

Perform these checks after `./scripts/rebuild.sh test` and before `switch`. Keep
the rebuild terminal open until networking and login are known-good. Package or
module evaluation does not establish that physical hardware works.

The read-only inventory script can collect initial evidence:

```bash
./scripts/hardware-inventory.sh > "$HOME/helix-hardware.txt"
sudo ./scripts/hardware-inventory.sh > "$HOME/helix-hardware-root.txt"
```

Reports may contain UUIDs, MAC addresses, labels, and model information. Review
them before sharing and never commit them.

## Desktop and NVIDIA

- Confirm Wayland with `echo "$XDG_SESSION_TYPE"` and
  `loginctl show-session "$XDG_SESSION_ID" -p Type`.
- Confirm the RTX 5080 driver with `lspci -nnk`, `lsmod`, and `nvidia-smi`.
- Run `glxinfo -B` and `vulkaninfo --summary`; the renderer must not be
  `llvmpipe`, `softpipe`, or another software renderer.
- Exercise every physical display connector, intended resolution, and maximum
  refresh rate in Plasma System Settings → Display & Monitor.
- Suspend with `systemctl suspend`, resume, and inspect
  `journalctl -b -p warning..alert` plus `nvidia-smi`. Repeat with monitors on
  each connector.

## Audio, camera, and radios

- Inspect `wpctl status`; test speakers, headphones, each microphone, mute, and
  volume controls in Plasma System Settings → Sound.
- Test live webcam video in Snapshot and inspect `v4l2-ctl --list-devices`,
  including any privacy switch.
- Scan and connect Wi-Fi through NetworkManager. Confirm its driver with
  `lspci -nnk` and status with `nmcli device status`.
- Pair a real Bluetooth peripheral in Plasma System Settings, inspect
  `bluetoothctl devices` and
  `rfkill list`, then reboot once to verify reconnection.

## Network, USB, and storage

- Check Ethernet using `nmcli device status`, `ip -brief address`, and
  `sudo ethtool INTERFACE` with the real interface reported by NetworkManager.
- Compare `lsusb -t` before and after testing every external USB port. Check
  `journalctl -k -b` for resets or enumeration errors.
- Verify storage with `lsblk -f`, `findmnt --real`, and `nvme list`; compare the
  result with the physical build and `hardware-configuration.nix`.
- Read health data with `sudo nvme smart-log DEVICE` and
  `sudo smartctl -x DEVICE` after reviewing each device path.
- Mount and eject a known removable drive through Files, confirming it with
  `findmnt` and `lsblk -f` before removal.

## Firmware and shutdown

- Run `fwupdmgr get-devices` and `fwupdmgr get-updates`. Review offers without
  applying firmware as part of configuration activation.
- Test a clean reboot and poweroff. On the next boot, inspect
  `journalctl -b -1 -p warning..alert` for hangs or device errors.
- Run `sudo ss -lntup` and investigate wildcard listeners. The default
  configuration intentionally enables no remote shell, discovery, sharing,
  container, or local-inference listener.

Record observed failures before adding hardware-specific workarounds. Settings
copied from another machine are not evidence about Helix.
