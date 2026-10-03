# Helix NixOS configuration

Current alpha: `v0.3.0-alpha.5`. `main` is the `v0.3.0-alpha.6` candidate;
see the [changelog](CHANGELOG.md) for what changed and the operator notes.

This is the canonical configuration for Helix, a NixOS 26.05 workstation with
Plasma 6, an optional Hyprland/UWSM session, and an NVIDIA RTX 5080. It uses
ordinary NixOS modules and a Nixpkgs release pinned in `nixpkgs.json`: no flakes, Home Manager, or a
host framework. A narrow repository-owned overlay
selects the immutably pinned first-party OpenClaw package.

The active configuration includes workstation, development, gaming, console emulation,
a separate hamCade arcade integration, and local LLM profiles, plus a Netdata child that streams metrics to Infernalnexus. Ollama runs
on `127.0.0.1:11434`; SSH is the only service intentionally exposed through the
firewall. Hardware support includes PipeWire, Bluetooth, native DualSense
support, redistributable firmware, NVIDIA open kernel modules, ckb-next for the
Corsair K70, and fan control.

## Repository layout

```text
configuration.nix          module imports, helix.<feature>.enable choices, assertions
hardware-configuration.nix generated facts for the currently installed system
config/                    host facts (helix.nix, infernalnexus.nix) and assets
lib/                       helpers for repeated module patterns
hardware/                  device and driver policy
desktop/                   Plasma, Hyprland, browsers, applications, and theme
system/                    boot, users, networking, NAS, and storage
services/                  OpenSSH, monitoring, and routine native maintenance
profiles/                  optional features behind helix.<feature>.enable options
packages/                  base package set and custom package definitions
shell/                     interactive shell and Git client integration
scripts/                   checks, rebuilds, inventory, backup, and recovery
docs/                      focused operating guides
```

`hardware-configuration.nix` is generated machine evidence. Do not edit or
reformat it during ordinary changes.

## Routine operation

Run fast validation without activating or building the complete workstation:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
```

Build the complete candidate separately when the change warrants it:

```bash
./scripts/rebuild.sh dry-build
```

Release qualification uses the explicit expensive gate:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh --full'
```

Normal pull-request CI does not rebuild the CUDA-enabled Ollama or MAME closures.

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
`helix-update` fast-forwards to reviewed `main`, then validates, builds, diffs,
tests and switches. Nixpkgs updates are pull requests made with
`./scripts/bump-nixpkgs.sh`. `helix-update` never runs garbage collection. `helix-git-credential-repair`
repairs GitHub HTTPS authentication without pinning `gh` to a garbage-collectable
Nix store path. Use `helix-theme list`,
`helix-theme current`, or `helix-theme NAME` to inspect and switch appearance.

## Installed-system compatibility

Helix was freshly installed on NixOS 26.05, and its permanent compatibility
floor is `system.stateVersion = "26.05"`. Future Nixpkgs upgrades must not raise
that value. The backup, restore, and hardware-continuity tools remain available
for disaster recovery and any deliberately planned future reinstall; see
[docs/reinstall.md](docs/reinstall.md).

## Focused guides

- [Changelog](CHANGELOG.md)
- [Architecture and ownership](docs/architecture.md)
- [Normal installation and recovery](docs/installation.md)
- [Routine backups](docs/backup.md)
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
- [Evaluation and consolidation roadmap](docs/roadmap.md)

Repository branch hygiene is deliberately conservative. Preview branches that are
already merged into `origin/main` with:

```bash
./scripts/prune-merged-branches.sh
```

Delete only those proven-merged branches with `--delete`; release and rollback
branches are always preserved, as are branches with open pull requests.

Hardware evaluation and builds do not prove physical devices work. Use the
hardware checklist after temporary activation and before switching.
