# Helix NixOS configuration

This repository is the traditional `/etc/nixos` configuration for Helix: a
minimal GNOME workstation with an NVIDIA RTX 5080. It deliberately starts
boring. Every persistent choice should either support known hardware, provide a
basic workstation function, or document a useful NixOS concept.

The checked-in `hardware-configuration.nix` is the real generated module for
Helix. Preserve it byte-for-byte when changing maintained policy modules.

## Why there are no flakes or Home Manager

NixOS modules and channels are enough for one system. The ordinary command
`nixos-rebuild` reads `/etc/nixos/configuration.nix`, resolves `<nixpkgs>` from
the root user's Nix channel, evaluates the imported modules, and builds a new
system generation. Avoiding flakes keeps that basic path visible. Avoiding Home
Manager keeps user preferences out of system policy and removes a second module
and activation system while Helix is young.

Neither decision is a claim that those tools are bad. They solve problems this
single-host learning configuration does not currently have.

## Layout

```text
/etc/nixos/
├── configuration.nix          # readable top-level import index
├── hardware-configuration.nix # generated machine facts; never hand-edit
├── hardware/
│   ├── nvidia.nix             # RTX 5080 driver, KMS, suspend support
│   ├── audio.nix              # PipeWire and microphone/audio discovery
│   ├── bluetooth.nix          # BlueZ policy
│   └── firmware.nix           # redistributable firmware policy
├── desktop/
│   ├── gnome.nix              # GDM/GNOME and disabled sharing services
│   └── applications.nix       # deliberately small graphical application set
├── system/
│   ├── boot.nix               # verified UEFI systemd-boot and sleep policy
│   ├── networking.nix         # NetworkManager, hostname, firewall
│   ├── users.nix              # the local tristan account (no secret material)
│   └── locale.nix             # time zone, locale, and keyboard policy
├── packages/
│   ├── base.nix               # universal retrieval and file inspection tools
│   ├── workstation.nix        # everyday desktop and command-line tools
│   ├── development.nix        # editor, compilers, runtimes, and code checks
│   ├── hardware-tools.nix     # hardware diagnostics (no services)
│   ├── fonts.nix              # conservative workstation font set
│   ├── gaming.nix             # gaming packages (no system policy)
│   └── local-llm.nix          # NVIDIA-enabled Ollama package
├── profiles/
│   ├── workstation.nix        # workstation tools, diagnostics, and fonts
│   ├── development.nix        # software development tools
│   ├── gaming.nix             # Steam, 32-bit graphics, and GameMode policy
│   └── local-llm.nix          # loopback-only CUDA Ollama service
├── services/
│   └── maintenance.nix        # firmware service and safe store optimisation
├── scripts/
│   └── hardware-inventory.sh  # read-only inventory collector
└── README.md
```

`configuration.nix` imports each file. Modules do not execute in list order:
NixOS merges all their option definitions into one configuration, checks option
types and assertions, and then derives services and files from the result. Two
modules can safely contribute different packages to `environment.systemPackages`;
incompatible singleton values instead produce a useful evaluation conflict.

## Facts, policy, and diagnostics

| Kind | Examples | Treatment |
| --- | --- | --- |
| Generated hardware facts | filesystem UUIDs, swap, initrd modules, CPU vendor | Generated on Helix and kept in `hardware-configuration.nix` |
| Maintained policy | GNOME, NetworkManager, NVIDIA open modules, packages | Reviewed Nix source in the other modules |
| Temporary diagnostics | `lspci`, `nvidia-smi`, `journalctl`, inventory output | Run interactively; output is not persistent configuration |
| Persistent runtime state | passwords, Wi-Fi secrets, Bluetooth pairings | Managed locally under `/etc` or `/var`; never committed |

The kernel, udev, NetworkManager, PipeWire, and GNOME dynamically discover
ordinary PCI/USB controllers, Ethernet, Wi-Fi, audio endpoints, cameras,
microphones, monitors, and removable drives. Hardware-specific module arguments
should be added only when the inventory or a real failure proves they are
needed. Storage declarations and boot-critical drivers remain in the generated
module.

## Required review before the first rebuild

1. Preserve the real `/etc/nixos/hardware-configuration.nix`. Confirm that it
   accounts for root/boot filesystems, swap, initrd storage modules,
   `nixpkgs.hostPlatform`, and exactly the detected CPU vendor's microcode
   option.
2. In `configuration.nix`, keep the installation's original
   `system.stateVersion` at `25.11`. Updating NixOS later is **not** a reason to
   change it.
3. Confirm `Pacific/Auckland`, `en_NZ.UTF-8`, and the US keymap in
   `system/locale.nix`.
4. Confirm that `tristan` is the desired account name and set its password
   locally with `sudo passwd tristan`. No password or hash is provided here.
5. Keep the verified UEFI systemd-boot settings in `system/boot.nix`. Disk
   layout, boot-critical drivers, and swap remain in the generated hardware
   module.
6. Use the inventory to record the CPU/chipset, network controllers and their
   drivers, audio devices, USB topology, cameras, storage, monitors, and any
   Thunderbolt/USB4 controller. Keep `services.hardware.bolt` disabled unless a
   suitable controller is present.

## Gather the hardware inventory

The script is read-only: it prints system state and does not install packages,
refresh firmware metadata, change radio state, mount disks, or write a report.
Run it once as the normal user, and again with `sudo` if SMART data or the system
journal was permission-limited:

```bash
./scripts/hardware-inventory.sh > "$HOME/helix-hardware.txt"
sudo ./scripts/hardware-inventory.sh > "$HOME/helix-hardware-root.txt"
```

Review those files before sharing them: `lsblk`, `ip`, and other tools can expose
UUIDs, MAC addresses, labels, and identifying model data. Do not commit the raw
reports.

The configured diagnostic packages provide `lspci` (`pciutils`), `lsusb`
(`usbutils`), `smartctl` (`smartmontools`), `nvme` (`nvme-cli`), `sensors`
(`lm_sensors`), `inxi`, `ethtool`, `iw`, `v4l2-ctl` (`v4l-utils`), `glxinfo`
(`mesa-demos`), and `vulkaninfo` (`vulkan-tools`). `lsblk`, `findmnt`, `lscpu`,
`rfkill`, and `dmesg` are standard system tools. `fwupdmgr` comes with the
enabled fwupd service. `nixos-hardware-check` is not assumed because it is not a
standard NixOS command in the current stable package set.

## Install these files without losing generated hardware data

Run these commands from the repository root. The backup is deliberately outside
the source tree:

```bash
backup="/etc/nixos.backup-$(date +%Y%m%d-%H%M%S)"
sudo cp -a /etc/nixos "$backup"

sudo install -d -m 0755 /etc/nixos/{hardware,desktop,system,packages,profiles,services,scripts}
sudo install -m 0644 configuration.nix /etc/nixos/configuration.nix
sudo install -m 0644 hardware-configuration.nix /etc/nixos/hardware-configuration.nix
sudo install -m 0644 hardware/*.nix /etc/nixos/hardware/
sudo install -m 0644 desktop/*.nix /etc/nixos/desktop/
sudo install -m 0644 system/*.nix /etc/nixos/system/
sudo install -m 0644 packages/*.nix /etc/nixos/packages/
sudo install -m 0644 profiles/*.nix /etc/nixos/profiles/
sudo install -m 0644 services/*.nix /etc/nixos/services/
sudo install -m 0755 scripts/hardware-inventory.sh /etc/nixos/scripts/
sudo install -m 0644 README.md /etc/nixos/README.md

sudo test -s /etc/nixos/hardware-configuration.nix
sudoedit /etc/nixos/configuration.nix
```

If this is a fresh installation target mounted under `/mnt`, generate the
hardware file for that target and use `/mnt/etc/nixos` instead of `/etc/nixos`:

```bash
sudo nixos-generate-config --root /mnt
```

Do not apply this configuration to a different machine without generating that
machine's own hardware module. Do not apply it until the required review above
is complete.

## Inspect, test, and activate a rebuild

First evaluate and build without changing the booted or active generation:

```bash
sudo nixos-rebuild dry-build
sudo nixos-rebuild build
readlink -f ./result
nix --extra-experimental-features nix-command store diff-closures /run/current-system ./result
```

`dry-build` reports what would be built or downloaded. `build` creates the
`result` symlink but does not activate it. The final command compares package
closures; it enables the newer `nix` command only for that invocation and does
not introduce flakes.

Activate the result temporarily first:

```bash
sudo nixos-rebuild test
```

`test` changes the running system but does not make the generation the default
for the next boot. After completing the important checks, persist it:

```bash
sudo nixos-rebuild switch
```

Do not use automatic login as a workaround for a missing password. From a root
shell, set the local credential with `sudo passwd tristan` before logging out.

## Generations and rollback

List system generations with:

```bash
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

If a new configuration cannot reach the desktop, reboot and select an older
NixOS generation in the boot loader menu. Once booted into it, make that
generation the active default with:

```bash
sudo nixos-rebuild switch --rollback
```

Automatic garbage collection is intentionally disabled so early rollback
generations are not silently removed. Delete old generations only after Helix
has been stable and the rollback consequences are understood.

## Channel updates and safe upgrades

This configuration follows the traditional root `nixos` channel. Inspect it and
read the target release notes before changing releases:

```bash
sudo nix-channel --list
sudo nix-channel --update nixos
sudo nixos-rebuild build --upgrade
nix --extra-experimental-features nix-command store diff-closures /run/current-system ./result
sudo nixos-rebuild test --upgrade
sudo nixos-rebuild switch --upgrade
```

For a release upgrade, first point the `nixos` channel at the intended stable
release URL, update it, and build/test before switching. Leave
`system.stateVersion` at its installation value. Do not combine a channel
upgrade with unrelated hardware or desktop changes; small generations are much
easier to diagnose and roll back.

## Make small changes

To add one package, edit the single-purpose file under `packages/`, add its Nix
attribute to `environment.systemPackages`, then run `nixos-rebuild build` and
`test`. Search the current channel with `nix search nixpkgs <name>` or the NixOS
package search site. Installing a package provides binaries; it does not usually
enable a service.

To enable a service, find its current option with:

```bash
man configuration.nix
nixos-option services.<name>.enable
```

Add the option to the most relevant existing module, then build and test. Check
whether it listens on a port, needs a firewall rule, stores secrets, or overlaps
with an existing service. Do not add an `enable = false` line merely to catalogue
every service NixOS could run.

Create a new module only when a concern has several related settings or would
make an existing file hard to read. A conventional module starts like this:

```nix
{ pkgs, ... }:

{
  # Explain the operational reason for the option.
  services.example.enable = true;
}
```

Save it near the concern and add a relative import in `configuration.nix`.
Avoid custom options, helper frameworks, and one-line files until repeated real
configuration demonstrates that an abstraction would clarify the system.

## Secrets and Git

It is reasonable to make `/etc/nixos` a Git repository. Keep ownership and
permissions appropriate, review every staged diff, and never add password
hashes, private keys, Wi-Fi credentials, VPN profiles, tokens, raw hardware
reports, or backups:

```bash
cd /etc/nixos
sudo git init
sudo git status --short
sudo git diff --cached
```

The generated `hardware-configuration.nix` normally contains machine identifiers
such as filesystem UUIDs but not credentials. Decide deliberately whether the
repository is private before tracking it. NetworkManager secrets, account
passwords, Bluetooth pairings, and fwupd state belong outside this tree. Never
put secrets into the Nix store: store paths are readable by local users.

## Hardware validation checklist

Perform this after `nixos-rebuild test`, before `switch`. Keep the terminal used
for the rebuild open until networking and login are known-good.

- [ ] **GNOME is a Wayland session:** log in through GDM, then run
  `echo "$XDG_SESSION_TYPE"` and
  `loginctl show-session "$XDG_SESSION_ID" -p Type`. Both should report
  `wayland`.
- [ ] **The NVIDIA driver owns the RTX 5080:** run
  `lspci -nnk | sed -n '/VGA\|3D controller/,+3p'`, `lsmod | grep '^nvidia'`,
  and `nvidia-smi`. The GPU and stable driver should be listed without errors.
- [ ] **Acceleration is hardware-backed:** run `glxinfo -B` and
  `vulkaninfo --summary`. The renderer/device should be NVIDIA, never
  `llvmpipe`, `softpipe`, or another software renderer.
- [ ] **Every monitor, output, resolution, and refresh rate works:** inspect
  GNOME Settings → Displays, exercise each physical connector, and compare
  `for f in /sys/class/drm/card*-*/status; do echo "$f: $(cat "$f")"; done`
  with the connected hardware. Test the intended maximum refresh rate rather
  than assuming that a visible picture is sufficient.
- [ ] **Suspend and resume preserve the desktop:** save work, run
  `systemctl suspend`, wake the machine, then check
  `journalctl -b -p warning..alert` and `nvidia-smi`. Repeat with monitors on
  each connector; watch for a black screen or lost audio device.
- [ ] **Speakers/headphones and microphone work:** inspect `wpctl status`, select
  each real endpoint in GNOME Settings → Sound, play test audio, record a short
  microphone sample, and verify mute/volume controls.
- [ ] **Ethernet works with the expected driver and speed:** run
  `nmcli device status`, `ip -brief address`, and
  `sudo ethtool <ethernet-interface>`. Replace the placeholder with the name
  reported by `nmcli`; do not add that transient name to Nix merely for testing.
- [ ] **Wi-Fi scans and connects:** run `nmcli device wifi list` and connect from
  GNOME Settings. Confirm the driver with
  `lspci -nnk | sed -n '/Network controller/,+3p'`.
- [ ] **Bluetooth pairs and reconnects:** pair a real peripheral in GNOME
  Settings, then inspect `bluetoothctl list`, `bluetoothctl devices`, and
  `rfkill list`. Reboot once to check reconnection.
- [ ] **The webcam and microphone are usable:** open Snapshot, verify live video,
  then run `v4l2-ctl --list-devices`. Test any privacy switch and every intended
  camera mode.
- [ ] **USB ports and controllers work:** compare `lsusb -t` before and after
  inserting a known device into every external port; verify expected speeds and
  check `journalctl -k -b` for resets or enumeration errors.
- [ ] **NVMe and other storage are correct:** run `lsblk -f`, `findmnt --real`,
  `nvme list`, and compare sizes/models/filesystems with the physical build and
  `hardware-configuration.nix`. Check that no expected device is absent.
- [ ] **Storage health data is readable:** run `sudo nvme smart-log <device>` for
  each NVMe namespace/controller as appropriate and
  `sudo smartctl -x <device>` for each supported drive. These commands read
  health data; review device paths carefully.
- [ ] **Firmware devices are visible:** run `fwupdmgr get-devices` and
  `fwupdmgr get-updates`. Review offered updates, but do not apply them as part
  of the first configuration activation.
- [ ] **Removable storage mounts and ejects cleanly:** insert one known USB drive,
  mount it through Files, confirm it in `findmnt` and `lsblk -f`, then use the
  graphical eject action before removal.
- [ ] **Shutdown and reboot are clean:** after the other checks, run
  `systemctl reboot`, then later `systemctl poweroff`; inspect the next boot with
  `journalctl -b -1 -p warning..alert` for hangs or device errors.
- [ ] **No unwanted server ports listen:** run `sudo ss -lntup`. Investigate every
  wildcard (`0.0.0.0` or `[::]`) listener. This configuration does not enable
  SSH, printing, Avahi, remote desktop, Samba, Syncthing, containers,
  virtualisation, or web/file-sharing servers.

Record real failures next to the inventory before adding a workaround. A module
parameter copied from another computer is not evidence about Helix.

## NVIDIA choices and current references

The configuration targets the NixOS 25.11 option model:
`services.displayManager.gdm`, `services.desktopManager.gnome`,
and `hardware.graphics`. NixOS 25.11 has no `hardware.nvidia.branch` option, so
Nixpkgs selects the appropriate stable driver. DRM modesetting is required for
reliable Wayland operation. The GeForce RTX 5080 uses NVIDIA's open kernel
modules while retaining the matching proprietary user-space graphics drivers.

- [NixOS 25.11 manual](https://nixos.org/manual/nixos/stable/)
- [NixOS 25.11 option reference](https://nixos.org/manual/nixos/stable/options)
- [Official NixOS NVIDIA guidance](https://wiki.nixos.org/wiki/NVIDIA)
- [NVIDIA open kernel module documentation](https://download.nvidia.com/XFree86/Linux-x86_64/570.144/README/kernel_open.html)
- [NVIDIA supported GPU table](https://download.nvidia.com/XFree86/Linux-x86_64/595.45.04/README/supportedchips.html)
