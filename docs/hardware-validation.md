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

The generated hardware configuration defines no swap. Hibernation is not
supported unless swap is deliberately designed and validated later; suspend
testing below does not imply hibernation support.

## Desktop and NVIDIA

- In SDDM, confirm both Plasma (Wayland) and Hyprland are selectable. Test
  Plasma first, then Hyprland, then log out with `Super+Shift+E` and return to
  Plasma. Confirm the previous-session behavior remains controlled by SDDM.
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
- Repeat renderer, connector, refresh-rate, screen-sharing, suspend/resume, and
  cursor checks in Hyprland; evaluation alone cannot validate NVIDIA behavior.

## Audio, camera, and radios

- Inspect `wpctl status`; test speakers, headphones, each microphone, mute, and
  volume controls in Plasma System Settings → Sound.
- Test live webcam video in an installed video-conferencing or browser
  application and inspect `v4l2-ctl --list-devices`, including any privacy switch.
- Scan and connect Wi-Fi through NetworkManager. Confirm its driver with
  `lspci -nnk` and status with `nmcli device status`.
- Pair a real Bluetooth peripheral in Plasma System Settings, inspect
  `bluetoothctl devices` and
  `rfkill list`, then reboot once to verify reconnection.

## Corsair K70 RGB

Helix's original Corsair K70 RGB reports USB ID `1b1c:1b13` and kernel name
`Corsair Corsair K70 RGB Gaming Keyboard`. Before activation it uses
`usbhid`/`hid-generic`, exposes two USB interfaces and input events
`/dev/input/event25`, `/dev/input/event26`, and `/dev/input/event27`, and has no
ckb-next daemon or RGB control. Event numbers are assigned dynamically and may
change after reconnecting or rebooting.

The supported `hardware.ckb-next` module supplies `ckb-next.service`, the GUI,
daemon, and device rules. It does not flash firmware or select a lighting
profile, and no GUI autostart is added: ordinary input and the daemon do not
depend on opening the GUI.

After activation, inspect the real device and service:

```bash
lsusb
systemctl status ckb-next.service
journalctl -b -u ckb-next.service
libinput list-devices
```

- Confirm normal typing with no missing, repeated, or duplicate keystrokes in
  Plasma, Hyprland, and a text-console login.
- Test media keys, volume wheel, mute, and supported brightness/profile keys.
- Open ckb-next manually and confirm RGB control without overwriting the
  keyboard's existing onboard profile or flashing firmware.
- Unplug and reconnect the keyboard, checking the journal and input devices.
- Suspend and resume, then repeat typing, media, volume, mute, and RGB tests.
- Compare `/proc/bus/input/devices` and `libinput list-devices` before and after
  activation to ensure multiple interfaces do not produce duplicate input.

These are physical tests; a successful build does not prove they pass.

## Media applications

- [ ] Spotify launches and plays audio.
- [ ] VLC and mpv play the same representative local video.
- [ ] Haruna plays the same video through its graphical interface.
- [ ] Strawberry can browse and play a local album.
- [ ] Plex Desktop reaches the existing Plex server after sign-in.
- [ ] GridPlayer displays multiple local videos simultaneously.
- [ ] Files beneath `/mnt/infernalnexus/nas1` open successfully.
- [ ] PipeWire audio works in every relevant player.
- [ ] NVIDIA hardware decoding is inspected separately rather than assumed.

## Graphite + Fern appearance

- [ ] SDDM is dark with readable login fields and clear password focus.
- [ ] Plasma is dark immediately after login on every monitor.
- [ ] The panel, tray, menus, notifications, task switcher, lock screen, and
      logout/shutdown screen are dark.
- [ ] The Graphite + Fern wallpaper appears on every monitor.
- [ ] Active and inactive windows, selected text, and disabled controls remain readable.
- [ ] Dolphin, System Settings, Ark, Haruna, Strawberry, VLC, and ckb-next are dark.
- [ ] At least one GTK 3 and one GTK 4 application, their file pickers, and portals are dark.
- [ ] Ghostty, Konsole, and VS Code use graphite surfaces with restrained fern focus states.
- [ ] Obsidian follows dark mode or its documented per-vault setting works.
- [ ] 1Password is dark; Spotify and Plex remain dark.
- [ ] Firefox, Chrome, Chromium, and Zen browser chrome are dark and websites
      report a dark preference.
- [ ] Dark Reader appears in managed browsers, can be disabled per site, and
      does not blindly invert photographs, video, or PDFs.
- [ ] Existing 1Password extensions remain installed and connected.
- [ ] In Hyprland, the wallpaper, borders, Waybar, Mako, Fuzzel, Qt, and GTK
      applications are dark and logout still works.

## 1Password

- [ ] The desktop app launches, its tray integration appears, and Quick Access works.
- [ ] System authentication can be enabled.
- [ ] `op --version` works and CLI integration authenticates through the unlocked app.
- [ ] Chrome, Chromium, and Firefox extensions appear and connect.
- [ ] Zen's manually installed official extension connects.
- [ ] Locking and unlocking is shared where supported.
- [ ] Managed built-in password prompts no longer compete with 1Password.
- [ ] Existing browser passwords remain intact.
- [ ] The SSH agent works after it is enabled in the app.
- [ ] Ordinary SSH still works while 1Password is locked or closed.

## Network, USB, and storage

After activation, verify the SSH daemon and listener locally, then connect from
a machine whose public key has already been authorized for `tristan`:

```bash
systemctl status sshd
ss -ltn | grep ':22'
ssh tristan@helix
```

- Check Ethernet using `nmcli device status`, `ip -brief address`, and
  `sudo ethtool INTERFACE` with the real interface reported by NetworkManager.
- Compare `lsusb -t` before and after testing every external USB port. Check
  `journalctl -k -b` for resets or enumeration errors.
- Verify storage with `lsblk -f`, `findmnt --real`, and `nvme list`; compare the
  result with the physical build and `hardware-configuration.nix`.
- Read health data with `sudo nvme smart-log DEVICE` and
  `sudo smartctl -x DEVICE` after reviewing each device path.
- Mount and eject a known removable drive through Dolphin, confirming it with
  `findmnt` and `lsblk -f` before removal.

## Firmware and shutdown

- Run `fwupdmgr get-devices` and `fwupdmgr get-updates`. Review offers without
  applying firmware as part of configuration activation.
- Test a clean reboot and poweroff. On the next boot, inspect
  `journalctl -b -1 -p warning..alert` for hangs or device errors.
- Run `sudo ss -lntup` and investigate wildcard listeners. SSH is intentionally
  exposed on TCP port 22. Ollama intentionally listens only on loopback at
  `127.0.0.1:11434`; it must not appear on a wildcard or external address.

Record observed failures before adding hardware-specific workarounds. Settings
copied from another machine are not evidence about Helix.

## Infernalnexus NAS

After activation, complete the focused setup and diagnostic steps in
[nas.md](nas.md), then verify:

- [ ] Helix boots normally while `192.168.1.8` is offline.
- [ ] The automount waits without mounting before first access.
- [ ] Accessing `/mnt/infernalnexus/nas1` mounts the share.
- [ ] Tristan can list, create, rename, and delete a temporary test file where
      the NAS account permits it.
- [ ] The mount disconnects after its idle timeout and later access remounts it.
- [ ] Authentication failure is clear and does not destabilise the desktop.
- [ ] Shutdown remains clean while the NAS is unavailable.

These checks require the real network, NAS, and credentials; evaluation cannot
establish that they pass. Static unit validation and dry activation do not
qualify sustained access; exercise real reads and permitted writes during the
full runtime test.
