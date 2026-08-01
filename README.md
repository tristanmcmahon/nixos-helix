# Helix NixOS configuration

This repository is the canonical configuration for Helix, a NixOS 25.11 Plasma 6
workstation with an NVIDIA RTX 5080. It uses traditional NixOS modules and the
root Nix channel: no flakes, Home Manager, overlays, or host framework.

The design keeps universal packages small and separates normal workstation
tools from development tools. The conservative gaming profile is enabled;
local inference remains opt-in. `hardware-configuration.nix` is the real
generated module for this machine and must not be edited or reformatted.

## Layout

```text
.
├── configuration.nix          # top-level import index and state version
├── hardware-configuration.nix # generated filesystems and boot hardware facts
├── hardware/                  # NVIDIA, audio, Bluetooth, and firmware policy
├── desktop/                   # SDDM, Plasma 6, and graphical applications
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
development, and gaming profiles. The initial gaming layer contains Steam,
GameMode, MangoHud, 32-bit graphics, and 32-bit audio support. Local LLM remains
disabled. See [docs/profiles.md](docs/profiles.md) for profile boundaries and
validation commands.

## Canonical source and routine operation

Edit this checkout under `~/Projects/nixos-helix`. `/etc/nixos` is only the
installer-created fallback; it is not a second maintained copy.

## One-command installation

From the repository root, run:

```bash
./scripts/install-helix.sh
```

It requires a clean checkout, fast-forwards `main` from `origin`, and runs the
complete validation suite before it can activate anything. It asks separately
before persistent activation and before rebooting.

The manual rebuild workflow below remains useful for debugging and incremental
configuration changes.

The helper resolves this repository from its own path, so it works from any
directory:

```bash
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh build
./scripts/rebuild.sh test
./scripts/rebuild.sh switch
```

The equivalent explicit form is:

```bash
sudo nixos-rebuild dry-build \
  -I "nixos-config=$PWD/configuration.nix"
```

Run `./scripts/check.sh` before activation. It checks formatting, shell scripts,
Git whitespace, the default gaming-enabled system, and the dormant local-LLM
profile. A build or dry build does not activate anything. `test` changes only
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
- [Local development, VS Code, GitHub, and Codex](docs/local-development.md)
- [Package and profile boundaries](docs/profiles.md)
- [Real-hardware validation checklist](docs/hardware-validation.md)

Hardware evaluation is not proof that devices work. Complete the hardware
checklist after `test` and before making a new generation permanent.
