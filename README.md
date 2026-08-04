# Helix NixOS configuration

This repository is the canonical configuration for Helix, a NixOS 26.05 Plasma 6
workstation with an NVIDIA RTX 5080 and an experimental Hyprland login option. It uses traditional NixOS modules and the
root Nix channel: no flakes, Home Manager, overlays, or host framework.

The design keeps universal packages small and separates normal workstation
tools from development tools. The conservative gaming profile is enabled;
local inference remains opt-in. `hardware-configuration.nix` is the real
generated module for this machine and must not be edited or reformatted.

## Layout

```text
.
├── release.nix                # maintained release, channel, and state contract
├── configuration.nix          # top-level module import index
├── hardware-configuration.nix # generated filesystems and boot hardware facts
├── hardware/                  # NVIDIA, audio, Bluetooth, and firmware policy
├── desktop/                   # SDDM, Plasma 6, optional Hyprland, and applications
├── shell/                     # declarative interactive shell environment
├── system/                    # boot, locale, networking, and users
├── packages/                  # package sets without service policy
├── profiles/                  # composable workstation and optional features
├── services/                  # routine system maintenance
├── scripts/                   # rebuild, validation, and inventory commands
├── docs/                      # focused operating and validation guides
└── shell.nix                  # bootstrap repository tools
```

## Active configuration

`configuration.nix` enables the base packages plus the workstation,
development, and gaming profiles. The workstation applications include Firefox,
Chrome, Chromium, Zen Browser, and Obsidian. The gaming layer contains Steam, GameMode, MangoHud,
32-bit graphics, and 32-bit audio support. Local LLM remains disabled. See
[docs/profiles.md](docs/profiles.md) for profile boundaries and validation
commands.

Vim is guaranteed in the base system as both `vi` and `vim`; `EDITOR` and
`VISUAL` both select Vim. The active declarative Bash layer packages
[`modern-bash`](https://github.com/tristanmcmahon/modern-bash) at commit
`55b1c4de6bc47e14285d55f6a1dfdf9fb494e806` and activates its secure prompt
without depending on an external checkout. NixOS owns that installation, so
the `modern-bash install` and `modern-bash uninstall` lifecycle commands are
disabled; update the pinned source in `shell/modern-bash.nix` instead.

Plasma remains the primary, known-good desktop. SDDM also offers an
experimental **Hyprland** session from its session chooser; selecting it does
not remove or change Plasma. Its reviewed configuration is installed from the
repository at `/etc/hypr/helix.conf`; changes are made declaratively in
`desktop/hyprland.nix`. See [docs/installation.md](docs/installation.md) for
the baseline bindings.

The attached Corsair K70 RGB (`1b1c:1b13`) is supported through the NixOS
`hardware.ckb-next` module. The build verifies its package, daemon, udev rules,
and `ckb-next.service`; physical behavior must still be tested after activation.

## hamkeydist

- Helix accepts public-key SSH login.
- Password and keyboard-interactive login are disabled.
- `mister` and `infernalnexus` remain defined through `networking.hosts`.
- SSH keys remain runtime user data and are not stored in this repository.

## Ghostty and workstation fonts

Ghostty's canonical configuration is
[`config/ghostty/config.ghostty`](config/ghostty/config.ghostty). A user service
deploys it as `~/.config/ghostty/config.ghostty`; the first differing local file
is preserved as `config.ghostty.pre-nixos`. Reload it with `Ctrl+Shift+,`, and
inspect it with `ghostty +show-config` or validate the repository copy with
`ghostty +validate-config --config-file=config/ghostty/config.ghostty`.
Available themes can be checked with `ghostty +list-themes`.
JetBrains Mono Nerd Font is the default monospace face; Maple Mono, Iosevka,
Noto Fonts, and Noto Color Emoji are installed alternatives. For persistent changes, edit and commit
the repository copy and rebuild instead of editing the deployed file.

## Canonical source and routine operation

Edit this checkout under `~/Projects/nixos-helix`. `/etc/nixos` is only the
installer-created fallback; it is not a second maintained copy.

## Normal operation and migration boundaries

An ordinary repository check is non-activating:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
```

A same-release rebuild uses the already-selected root channel:

```bash
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh test
```

`test` changes only the running system. After focused runtime validation,
`./scripts/rebuild.sh switch` also selects it as the persistent boot generation.

A major NixOS release migration is separate and must begin with an explicit
warning and root-channel change. It can change the kernel, drivers, desktop,
Nix, and the complete system closure; `system.stateVersion` remains `25.11`.
Run `./scripts/migrate-release.sh` and see [installation.md](docs/installation.md).

A fresh reinstall is destructive, may change filesystem UUIDs, and uses a newly
generated hardware configuration in a temporary checkout. The existing
in-place installation is release 26.05 with state version 25.11; a wiped fresh
installation is release 26.05 with state version 26.05. Fresh installation is
never performed by the normal installer; see [reinstall.md](docs/reinstall.md).

## Guided configuration installation

From the repository root, run:

```bash
./scripts/install-helix.sh
```

It requires a clean checkout and installs that exact checked-out commit without
switching branches or contacting Git. It runs the complete validation suite,
then asks separately before temporary and persistent activation and rebooting.

The manual rebuild workflow below remains useful for debugging and incremental
configuration changes.

The helper resolves this repository from its own path, so it works from any
directory:

```bash
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh build
./scripts/rebuild.sh dry-activate
./scripts/rebuild.sh test
./scripts/rebuild.sh switch
```

The equivalent explicit form is:

```bash
sudo nixos-rebuild dry-build \
  -I "nixos-config=$PWD/configuration.nix"
```

Run the development-shell check before activation. It checks formatting, shell scripts,
Git whitespace, recovery commands, isolated Bash startup, the Hyprland config,
both SDDM sessions, Corsair support, the default gaming-enabled system, and the
dormant local-LLM profile. A build or dry build does not activate anything. `test` changes only
the running system; `switch` also makes the result the default boot generation.

## Rollback

If a tested configuration breaks the desktop, reboot and choose an older NixOS
generation in systemd-boot. From a working older generation, restore it as the
default with:

```bash
sudo nixos-rebuild switch --rollback
```

A persistent nightly timer runs at 02:00, protects the active generation, keeps
the two newest alternatives, removes older system-generation links, and then
collects unreachable store paths. User profiles and channels are untouched, so
rollback is intentionally limited to the two retained alternatives.

## Focused guides

- [Installation and recovery](docs/installation.md)
- [Fresh reinstall qualification](docs/reinstall.md)
- [Local development, VS Code, GitHub, and Codex](docs/local-development.md)
- [Package and profile boundaries](docs/profiles.md)
- [Real-hardware validation checklist](docs/hardware-validation.md)
- [Infernalnexus NAS](docs/nas.md)
- [Media applications](docs/media.md)
- [Custom package pins](docs/custom-packages.md)
- [1Password integration](docs/onepassword.md)
- [Alpha 3 release notes](docs/alpha-3.md)
- [Helix Abyss appearance](docs/theme.md)
- [Alpha 4 release notes](docs/alpha-4.md)

Hardware evaluation is not proof that devices work. Complete the hardware
checklist after `test` and before making a new generation permanent.
