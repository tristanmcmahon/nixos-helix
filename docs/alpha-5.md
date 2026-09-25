# Alpha 5

Release target: `v0.3.0-alpha.5`

Alpha 5 is a substantial workstation checkpoint after Alpha 4. The most
important operational change is that **Helix now uses the Pi-hole on
`infernalnexus` as its normal system DNS resolver**.

## Important DNS behaviour change

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

## Other Alpha 5 highlights

Since Alpha 4, Helix has also gained:

- a local-only Prometheus/Grafana hardware-monitoring stack with long retention,
  NVIDIA/SMART/node exporters, CoolerControl integration, and guarded fan
  commissioning;
- a substantially expanded repository-owned Graphite theme family, per-session
  theme rotation, and Ghostty profile/surface selection;
- declarative local Ollama operation on the games NVMe with a five-model
  baseline, a 32K context setting, and an explicit model refresh helper;
- NAS-first emulation and hamCade integration, including read-only NAS ROM
  policy, local writable state, Doom/GZDoom tooling, and OpenClaw/Codex
  orchestration for the RetroArch path;
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

## Pi-hole ownership boundary

Pi-hole container lifecycle remains owned by `hamology`. Private DNS and
ingress policy live in `hamFence`. This repository owns only Helix's client-side
resolver selection.

That separation is intentional:

```text
hamology     -> deploys/runs Pi-hole
hamFence     -> private DNS names + DSM ingress policy
nixos-helix  -> chooses Pi-hole as Helix's system resolver
```

## Validation

Before switching Alpha 5:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh test
```

The release branch additionally runs:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh --full'
```

That expensive gate is intentionally not part of routine pull-request CI.

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
