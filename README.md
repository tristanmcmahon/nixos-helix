# Helix NixOS configuration

This is the canonical configuration for Helix, a NixOS 26.05 workstation with
Plasma 6, an optional Hyprland/UWSM session, and an NVIDIA RTX 5080. It uses
ordinary NixOS modules and the root Nix channel: no flakes, Home Manager,
flakes, Home Manager, or a host framework. A narrow repository-owned overlay
selects the immutably pinned first-party OpenClaw package.

The active configuration includes workstation, development, gaming, emulation,
and local LLM profiles, plus a local-only hardware-monitoring stack. Ollama runs
on `127.0.0.1:11434`; SSH is the only service intentionally exposed through the
firewall. Hardware support includes PipeWire, Bluetooth, native DualSense
support, redistributable firmware, NVIDIA open kernel modules, ckb-next for the
Corsair K70, long-history monitoring, and fan control.

## Repository layout

```text
configuration.nix          top-level module imports and release assertion
hardware-configuration.nix generated facts for the currently installed system
hardware/                  device and driver policy
desktop/                   Plasma, Hyprland, browsers, applications, and theme
system/                    boot, users, networking, NAS, and storage
services/                  OpenSSH, monitoring, and routine native maintenance
profiles/                  workstation, development, gaming, emulation, and local LLM
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

Native weekly garbage collection deletes generations older than 14 days, and
weekly store optimisation hard-links identical store files.

For normal maintenance, `helix-health` prints a compact workstation report and
`helix-update` performs a clean-tree, validate, build, diff, test, and switch
sequence. `helix-update` never runs garbage collection. Use `helix-theme list`,
`helix-theme current`, or `helix-theme NAME` to inspect and switch appearance.

## Installed-system compatibility

Helix was freshly installed on NixOS 26.05, and its permanent compatibility
floor is `system.stateVersion = "26.05"`. Future channel upgrades must not raise
that value. The backup, restore, and hardware-continuity tools remain available
for disaster recovery and any deliberately planned future reinstall; see
[docs/reinstall.md](docs/reinstall.md).

## Focused guides

- [Normal installation and recovery](docs/installation.md)
- [Reinstall and recovery](docs/reinstall.md)
- [Hardware validation](docs/hardware-validation.md)
- [Monitoring and fan control](docs/monitoring.md)
- [Infernalnexus NAS](docs/nas.md)
- [NAS-first emulation](docs/emulation.md)
- [Profiles and package boundaries](docs/profiles.md)
- [Local development](docs/local-development.md)
- [Graphite + Fern appearance](docs/theme.md)
- [Health, updates, GC, memory pressure, and OpenClaw pin](docs/operations.md)
- [Media applications](docs/media.md)
- [Custom package pins](docs/custom-packages.md)
- [1Password integration](docs/onepassword.md)

Hardware evaluation and builds do not prove physical devices work. Use the
hardware checklist after temporary activation and before switching.
