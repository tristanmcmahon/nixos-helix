# Installation and recovery

This repository is for the real Helix workstation. Its generated
`hardware-configuration.nix` contains Helix's filesystem UUIDs, initrd modules,
platform, and AMD microcode setting. Preserve it exactly. A different machine
must generate its own hardware module during installation; never copy Helix's
identifiers or run `nixos-generate-config` over this checkout.

## Fixed installation compatibility

Helix is maintained against NixOS 26.05 on the `nixos-26.05` root channel.
`system.stateVersion = "25.11"` records the original installation's persistent
state compatibility and must not change during the release upgrade. The
contract is centralized in `release.nix` and evaluation fails on another release.

Before a major upgrade, display and acknowledge:

```text
MAJOR NIXOS RELEASE UPGRADE
Current: 25.11
Target:  26.05
system.stateVersion remains 25.11
This changes the kernel, drivers, desktop packages and system closure.
```

Preserve the current generation and run the repository-owned migration helper.
It requires an exact confirmation phrase, stops the cleanup timer for the
qualification window, updates only the root channel, and verifies the selected
release:

```bash
./scripts/migrate-release.sh
```

For transparency, the state-changing operations inside it are
`sudo systemctl stop helix-nix-cleanup.timer`, `sudo nix-channel --add` using
the URL from `release.nix`, and `sudo nix-channel --update nixos`. The root
channel cannot be declared by the system configuration because Nixpkgs must be
selected before that configuration can evaluate.

Do not use `nixos-rebuild --upgrade` during this controlled migration. Do not
delete old generations or run garbage collection. An older boot generation is
the primary rollback. Reverting the root channel is a separate action, and a
Nix database schema upgrade may make a complete channel downgrade less direct.
After 26.05 is fully qualified, restore scheduled cleanup with:

```bash
sudo systemctl start helix-nix-cleanup.timer
```

Helix boots in UEFI mode with systemd-boot. The maintained boot module keeps EFI
variable access enabled and a five-second menu timeout. Storage layout and
boot-critical drivers remain in the generated hardware module.

The RTX 5080 uses NVIDIA's open kernel modules with the matching proprietary
user-space driver. Nixpkgs selects the stable driver without a package override.

## Recovery editor and shell

The minimal base closure includes Vim under both `vi` and `vim`, including on a
text console when the graphical desktop is unavailable. The supported NixOS
Vim module selects it as `EDITOR`; the base module also sets `VISUAL=vim`
to make the recovery-shell contract explicit.

Interactive Bash shells activate the immutable `modern-bash` 0.3.0 runtime
from `https://github.com/tristanmcmahon/modern-bash` at source commit
`55b1c4de6bc47e14285d55f6a1dfdf9fb494e806`. Its prompt, terminal capability
detection, optional Git context, and user configuration support are preserved.
No installer runs at shell startup, and the original checkout is not needed.
The system command rejects `modern-bash install` and `modern-bash uninstall`
because NixOS owns the installation. Update `shell/modern-bash.nix` and rebuild
instead of creating a competing mutable copy.

## Optional Hyprland session

Plasma 6 remains the normal desktop and SDDM remains the display manager. To
try Hyprland, use SDDM's session chooser before signing in and select
**Hyprland**. Log out and select **Plasma (Wayland)** to return; Hyprland has
not replaced or reconfigured Plasma.

The UWSM session passes `--config /etc/hypr/helix.conf` to the standard
Hyprland compositor command. NixOS installs that repository-owned baseline
declaratively; it never creates or changes files in the user's home directory.
Edit `desktop/hyprland.nix` and rebuild to change the baseline.

Baseline bindings are:

- `Super+Return`: Ghostty
- `Super+D`: Fuzzel application launcher
- `Super+Q`: close the active window
- `Super+Shift+E`: confirm logout and return to SDDM
- `Super+Arrow`: move focus
- `Super+1` through `Super+9`: select a workspace
- `Super+Shift+1` through `Super+Shift+9`: move the active window
- hardware audio keys: volume and mute through PipeWire

Waybar, Mako, Fuzzel, and the NetworkManager applet provide the minimal
session. Plasma's KDE polkit authentication agent is started so graphical
privilege prompts work. The normal NixOS Hyprland portal is added alongside
Plasma's KDE portal. NVIDIA,
multi-monitor, screen-sharing, suspend/resume, and peripheral behavior still
require real login testing before Hyprland can be considered validated.

## First use

Treat this checkout as the only maintained source. `/etc/nixos` may remain as
the installer-created fallback, but routine commands must select this checkout
explicitly:

```bash
cd ~/Projects/nixos-helix
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh dry-activate
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

This configuration follows the root `nixos` channel. Inspect it and read the
26.05 release notes before updating:

Inspect the selected root channel with `sudo nix-channel --list`. Channel
changes belong only to the explicit major-migration procedure above; ordinary
checks and rebuilds never update it.

Do not combine a release upgrade with unrelated hardware changes, and never
bump `system.stateVersion` merely because the channel changed.

The generated hardware configuration defines no swap. Hibernation is therefore
unsupported unless swap is deliberately designed and validated in a later change.

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
