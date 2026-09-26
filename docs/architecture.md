# Helix architecture and ownership

Helix is a single-host NixOS workstation configuration with deliberately explicit
ownership boundaries. The repository favours ordinary NixOS modules, generated
machine evidence, small imperative helpers where mutable runtime state requires
them, and tests that encode the behaviour the workstation must preserve.

## Ownership model

- `configuration.nix` composes the system. It should remain boring: imports,
  top-level feature enables, release assertions, and only genuinely global policy.
- `hardware-configuration.nix` is generated machine evidence. Ordinary changes
  must not edit or reformat it.
- `hardware/` owns device and driver policy.
- `desktop/` owns graphical-session policy and repository-managed appearance.
- `system/` owns boot, users, networking, storage, NAS access, locale, and other
  host-level behaviour.
- `services/` owns long-running services and their lifecycle policy.
- `packages/` defines software sets and repository-owned package definitions.
- `profiles/` composes packages plus the policy needed for a coherent use case.
- `scripts/` contains operator tooling, validation, and recovery helpers.
- `tests/` encodes system invariants that must remain true after refactoring.
- `docs/` explains operating procedures and decisions that cannot be inferred
  safely from the module graph alone.

## Sibling-project boundaries

`nixos-helix` owns the Helix machine: packages, mounts, service lifecycle,
client-side network choices and thin adapters that make separately developed
projects available on this host. It must not become a second implementation of
those projects' application policy.

The current boundaries are:

- `hamCade` owns arcade/MAME runtime policy, ES-DE, curation, DAT/audit logic,
  media and arcade mutable state. `nixos-helix` owns only the thin Helix
  package/launcher integration and a vendored dependency snapshot for
  credential-free evaluation/CI.
- `hamSteam` owns Steam-library policy and program behaviour.
  `nixos-helix` owns the Helix systemd user service/timer that runs it.
- `hamology` owns application/container lifecycle on `infernalnexus`,
  including the Pi-hole container.
- `hamFence` owns NAS networking, TLS, ingress, private DNS records, firewall
  and remote-access policy.
- `hamKeyDist` owns SSH identities, authorized-key distribution and managed
  SSH aliases. `nixos-helix` owns Helix's SSH server and firewall settings.

Host facts may be repeated where a client genuinely needs them, but authority
must not be duplicated. For example, Helix may choose `192.168.1.8` as its DNS
resolver; it must not deploy or configure the Pi-hole service itself.

## State model

Helix distinguishes four kinds of state:

1. **Declarative system state** belongs in NixOS modules and is recreated by a
   rebuild.
2. **Generated hardware evidence** is captured by NixOS tooling and reviewed
   rather than hand-maintained.
3. **Mutable user/application state** remains outside the Nix store unless Helix
   has a strong reason to own a narrow setting.
4. **Secrets** remain outside Git and the world-readable Nix store.

Repository-managed initialisers may create required directories or small runtime
state only after positively verifying their backing resource is present.

## Safety model

Automation may perform a repair only when the desired action is deterministic,
bounded, and non-destructive. Hardware identity, filesystem replacement,
partitioning, secret recovery, and other consequential choices require explicit
human approval.

A successful Nix evaluation or build proves configuration consistency, not
physical hardware behaviour. Runtime checks and the hardware-validation
procedures remain separate evidence.

## Network model

Services are loopback-only unless Helix intentionally exposes them. SSH is the
normal remotely reachable host service. Infernalnexus is an optional external
dependency and must not make the workstation unable to boot when the NAS is
offline.

Helix deliberately uses the Pi-hole on Infernalnexus as its sole system DNS
resolver while `helix.networking.pihole.enable` is true. Infernalnexus host and
SMB facts are centralized in `config/infernalnexus.nix`; router and LAN-wide
DHCP DNS remain outside this repository.

## Change model

Normal changes should preserve this sequence:

```text
edit
→ static validation and invariants
→ build candidate
→ inspect change
→ test activation
→ runtime health check where applicable
→ persistent switch
```

Dangerous recovery operations deliberately have additional manual gates.
Tests should grow when an incident reveals a durable rule worth preserving;
they should not merely mirror implementation details.
