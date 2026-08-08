# Helix NixOS configuration

This is the canonical configuration for Helix, a NixOS 26.05 workstation with
Plasma 6, an optional Hyprland/UWSM session, and an NVIDIA RTX 5080. It uses
ordinary NixOS modules and the root Nix channel: no flakes, Home Manager,
overlays, or host framework.

The active configuration includes workstation, development, gaming, and local
LLM profiles. Ollama runs locally on `127.0.0.1:11434`; SSH is the only service
intentionally exposed through the firewall. Hardware support includes
PipeWire, Bluetooth, redistributable firmware, NVIDIA open kernel modules, and
ckb-next for the Corsair K70.

## Repository layout

```text
configuration.nix          top-level module imports and release assertion
hardware-configuration.nix generated facts for the currently installed system
hardware/                  device and driver policy
desktop/                   Plasma, Hyprland, browsers, applications, and theme
system/                    boot, users, networking, NAS, and storage
services/                  OpenSSH and routine native maintenance
profiles/                  workstation, development, gaming, and local LLM
packages/                  package sets and custom package definitions
shell/                     immutable modern-bash integration
scripts/                   checks, rebuilds, inventory, backup, and recovery
docs/                      focused operating guides
```

`hardware-configuration.nix` is generated machine evidence. Do not edit or
reformat it during ordinary changes.

## Routine operation

Run validation without activating anything:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh dry-build
```

After reviewing a change, temporary and persistent activation remain explicit:

```bash
./scripts/rebuild.sh test
./scripts/rebuild.sh switch
```

`test` changes the running system until reboot; `switch` also selects the new
boot generation. If a generation fails, choose an older one from systemd-boot
or use `sudo nixos-rebuild switch --rollback` from a working generation.

Native weekly garbage collection deletes generations older than 30 days, and
weekly store optimisation hard-links identical store files.

## Imminent fresh reinstall

The current installation originated on NixOS 25.11, so its compatibility
`stateVersion` remains 25.11. The temporary fresh-install entry uses 26.05 for
the imminent wiped installation. This dual entry is the sole intentional
legacy bridge and will be removed after the fresh system passes postflight.
See [docs/reinstall.md](docs/reinstall.md).

## Focused guides

- [Normal installation and recovery](docs/installation.md)
- [Fresh reinstall](docs/reinstall.md)
- [Hardware validation](docs/hardware-validation.md)
- [Infernalnexus NAS](docs/nas.md)
- [Profiles and package boundaries](docs/profiles.md)
- [Local development](docs/local-development.md)
- [Helix Abyss appearance](docs/theme.md)
- [Media applications](docs/media.md)
- [Custom package pins](docs/custom-packages.md)
- [1Password integration](docs/onepassword.md)

Hardware evaluation and builds do not prove physical devices work. Use the
hardware checklist after temporary activation and before switching.
