# Installation and recovery

This repository is for the real Helix workstation. Its generated
`hardware-configuration.nix` contains Helix's filesystem UUIDs, initrd modules,
platform, and AMD microcode setting. Preserve it exactly. A different machine
must generate its own hardware module during installation; never copy Helix's
identifiers or run `nixos-generate-config` over this checkout.

## Fixed installation compatibility

`system.stateVersion = "25.11"` records the original installation's persistent
state compatibility. Channel upgrades do not change it.

Helix boots in UEFI mode with systemd-boot. The maintained boot module keeps EFI
variable access enabled and a five-second menu timeout. Storage layout and
boot-critical drivers remain in the generated hardware module.

The RTX 5080 uses NVIDIA's open kernel modules with the matching proprietary
user-space driver. NixOS 25.11 has no `hardware.nvidia.branch` option, so
Nixpkgs selects the stable driver without a package override.

## Recovery editor and shell

The minimal base closure includes Vim under both `vi` and `vim`, including on a
text console when the graphical desktop is unavailable. The supported NixOS
Vim module selects it as `EDITOR`; the base module also sets `VISUAL=vim`
because the NixOS 25.11 Vim module does not set that variable.

Interactive Bash shells activate the immutable `modern-bash` 0.3.0 runtime
from `https://github.com/tristanmcmahon/modern-bash` at source commit
`55b1c4de6bc47e14285d55f6a1dfdf9fb494e806`. Its prompt, terminal capability
detection, optional Git context, and user configuration support are preserved.
No installer runs at shell startup, and the original checkout is not needed.

## Optional Hyprland session

Plasma 6 remains the normal desktop and SDDM remains the display manager. To
try Hyprland, use SDDM's session chooser before signing in and select
**Hyprland**. Log out and select **Plasma (Wayland)** to return; Hyprland has
not replaced or reconfigured Plasma.

The first Hyprland launch copies a conservative system baseline to
`~/.config/hypr/hyprland.conf` only when that file does not exist. This is
necessary because the packaged Hyprland 0.52.1 reliably reads the per-user XDG config path,
not `/etc/xdg` as a fallback. Later launches never overwrite that file.

Baseline bindings are:

- `Super+Return`: Ghostty
- `Super+D`: Fuzzel application launcher
- `Super+Q`: close the active window
- `Super+Shift+E`: confirm logout and return to SDDM
- `Super+Arrow`: move focus
- `Super+1` through `Super+9`: select a workspace
- `Super+Shift+1` through `Super+Shift+9`: move the active window
- hardware audio keys: volume and mute through PipeWire

Waybar, Mako, the NetworkManager applet, clipboard/screenshot utilities,
brightness control, and media controls provide a minimal session. The normal
NixOS Hyprland portal is added alongside Plasma's KDE portal. NVIDIA,
multi-monitor, screen-sharing, suspend/resume, and peripheral behavior still
require real login testing before Hyprland can be considered validated.

## First use

Treat this checkout as the only maintained source. `/etc/nixos` may remain as
the installer-created fallback, but routine commands must select this checkout
explicitly:

```bash
cd ~/Projects/nixos-helix
./scripts/check.sh
./scripts/rebuild.sh test
```

Before `test`, confirm the expected account, New Zealand locale, systemd-boot
settings, and generated filesystem definitions. Set account passwords locally;
passwords and hashes do not belong in this repository or the Nix store.

After the checks in [hardware-validation.md](hardware-validation.md) pass, make
the generation persistent with:

```bash
./scripts/rebuild.sh switch
```

## Traditional channel workflow

This configuration follows the root `nixos` channel. Inspect it before an
update and read the target release notes:

```bash
sudo nix-channel --list
sudo nix-channel --update nixos
sudo nixos-rebuild build --upgrade \
  -I "nixos-config=$PWD/configuration.nix"
```

Do not combine a release upgrade with unrelated hardware changes, and never
bump `system.stateVersion` merely because the channel changed.

## Recovery

List generations with:

```bash
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

If the current generation cannot reach Plasma, select an older generation in
the systemd-boot menu. Once booted into it, make it the default again:

```bash
sudo nixos-rebuild switch --rollback
```

The nightly cleanup keeps the active system generation plus the two newest
other generations. It does not delete user profile generations or channels. A
missed 02:00 run executes after the next boot, and unreachable store paths are
collected only after obsolete system-generation links are removed.
