# Changelog

Release notes for Helix. Operating guides live in `docs/`.

## v0.3.0-alpha.6 (candidate)

Release candidate on `main`; tag it after the Helix qualification below passes.

### Operator notes

- **Nixpkgs is pinned** in `nixpkgs.json`. The root channel is no longer used.
  Update with `./scripts/bump-nixpkgs.sh` in a pull request; `helix-update`
  now fast-forwards to reviewed `main` (on `main` only) and builds its pin.
- **Backups**: create the restic password once (see `docs/backup.md`) and keep
  a copy in 1Password. Never regenerate it after the first backup.
- **Removed**: Zen Browser, the local Prometheus/Grafana history (history now
  lives on the Infernalnexus Netdata parent; `/var/lib/prometheus2` and
  `/var/lib/grafana` can be deleted by hand), and the dormant ChatGPT package.
- **Unfree software** is allowed by name in `configuration.nix`; a new unfree
  package fails evaluation until it is listed.
- **Reinstall tools** run through `./scripts/helix-reinstall.sh`.

### Added

- Claude Code and its Zed agent adapter, `helix-zed-agent-setup`, and
  `CLAUDE.md` (#84).
- Nightly restic backups to Infernalnexus (#87, #88).
- `helix.<feature>.enable` options for every feature, with a test that disables
  them all (#86).
- `CHANGELOG.md`, `vendor/sources.json` with `scripts/vendor-sync.sh` (#87).

### Changed

- Ghostty: eight profiles (Tide, Dusk, Sand and Frost added); new splits,
  tabs and windows get a random profile; `ghostty-theme` recolours the current
  surface on demand (#93).

- Host facts live in `config/helix.nix`; repeated patterns in `lib/helix.nix`;
  the reinstall scripts read the same facts (#86, #92).
- Themes render from `config/theme/palettes.nix` and explicit templates; Fuzzel
  menus now follow the theme (#86).
- The health gate is generated from each feature's critical units (#86).
- Netdata is a lightweight streaming child; Ollama uses flash attention with an
  8-bit KV cache (#90, #91, #92).
- Login applies the theme once; rebuilds no longer re-pull Ollama models; zram
  tuning; at most 20 boot entries (#89).
- `--full` evaluates once and no longer repeats evaluation invariants (#86, #92).

### Fixed

- OpenClaw: Node with bundled SQLite, a writable runtime config copy, and a
  read-only `.git`/editor config inside its sandbox (#84, #85, #86).
- The `--full` release gate (broken since #74), the Ghostty profile reset at
  login, `helix-update` channel handling, and documentation drift (#86).
- SSH from Ghostty splits, tabs and new windows sends `xterm-256color` again,
  fixing Backspace/Delete on mister and Infernalnexus (regressed with the
  per-surface colours; an invariant now guards it).
- The reinstall preflight and install procedure use the Nixpkgs pin.

## v0.3.0-alpha.5

Release target: `v0.3.0-alpha.5`

Alpha 5 is a substantial workstation checkpoint after Alpha 4. The most
important operational change is that **Helix now uses the Pi-hole on
`infernalnexus` as its normal system DNS resolver**.

### Important DNS behaviour change

Helix enables:

```nix
helix.networking.pihole = {
  enable = true;
  address = "192.168.1.8";
};
```

NetworkManager still owns DHCP addresses and routes, but DHCP-provided DNS is
ignored while this option is enabled. `192.168.1.8` is the sole configured
system resolver and there is deliberately no public fallback resolver that can
silently bypass Pi-hole.

This is a Helix-only change. Router and LAN-wide DHCP DNS remain unchanged.

Runtime qualification completed on 2026-09-26:

- Pi-hole on `infernalnexus` passed its hamology deployment/acceptance checks.
- Direct DNS queries from Helix to `192.168.1.8:53` succeeded.
- hamFence private records for `home.alienrobot.org` and
  `sonarr.home.alienrobot.org` resolved correctly through Pi-hole.
- ordinary Helix system DNS resolved `home.alienrobot.org`.
- trusted HTTPS to `https://home.alienrobot.org/` passed through DSM ingress
  to the loopback landing-page backend.

Rollback is explicit: set `helix.networking.pihole.enable = false` and rebuild,
or switch to the previous NixOS generation.

### Other Alpha 5 highlights

Since Alpha 4, Helix has also gained:

- a local-only Prometheus/Grafana hardware-monitoring stack with long retention,
  NVIDIA/SMART/node exporters, CoolerControl integration, and guarded fan
  commissioning;
- a substantially expanded repository-owned Graphite theme family, per-session
  theme rotation, and Ghostty profile/surface selection;
- declarative local Ollama operation on the games NVMe with a five-model
  baseline, a 32K context setting, and an explicit model refresh helper;
- NAS-first console emulation plus a separate hamCade arcade integration,
  keeping read-only NAS ROM policy and local writable state while making
  arcade/MAME ownership explicit;
- repository-owned OpenClaw integration and a pinned first-party package;
- workstation lifecycle tooling including `helix-health`, `helix-update`,
  improved rebuild output, memory-pressure policy, storage helpers, and stronger
  system invariants;
- broader automated validation, including dedicated emulation CI and additional
  configuration/invariant tests;
- a repository architecture cleanup that splits the validation suite and system
  invariants by domain, decomposes the emulation profile, centralizes
  Infernalnexus host/SMB facts, and hardens `helix-health` / `helix-update`;
- tiered CI: routine PR checks evaluate configuration and invariants without
  rebuilding CUDA/MAME, while `scripts/check.sh --full` remains the explicit
  release gate for the complete workstation closure.

### Pi-hole ownership boundary

Pi-hole container lifecycle remains owned by `hamology`. Private DNS and
ingress policy live in `hamFence`. This repository owns only Helix's client-side
resolver selection.

That separation is intentional:

```text
hamology     -> deploys/runs Pi-hole
hamFence     -> private DNS names + DSM ingress policy
nixos-helix  -> chooses Pi-hole as Helix's system resolver
```

### Validation

Before switching Alpha 5:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh test
```

Full closure validation remains available explicitly:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh --full'
```

Hosted Release CI is manual-dispatch only; release branch maintenance does not
automatically start the expensive closure build. Routine pull-request CI stays
on the quick validation/evaluation gate.

Resolver checks on the activated generation:

```bash
cat /etc/resolv.conf
getent ahostsv4 home.alienrobot.org
curl -fsS -o /dev/null https://home.alienrobot.org/
```

The configured resolver should be `192.168.1.8`, and
`home.alienrobot.org` should resolve to `192.168.1.8`.

After real-hardware validation:

```bash
./scripts/rebuild.sh switch
```

Alpha 5 remains an alpha: the repository deliberately keeps some subsystem
qualification work open, notably sustained NAS SMB testing and the evolving
emulation workflow. Those are documented operational limits rather than hidden
release blockers.

## Earlier releases

`v0.3.0-alpha.4`, `v0.3.0-alpha.3`, `v0.2.0` and `v0.1.0` are recorded as Git
tags; see their commit history.
