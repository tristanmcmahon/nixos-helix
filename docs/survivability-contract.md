# Helix survivability and reconstruction contract

Helix is one manually operated NixOS workstation, not an autonomous cluster.
The configuration is non-flake, without Home Manager, and is tied to an
immutable Nixpkgs revision. Sibling projects retain their own policy.

## Acceptance guarantees

| Property | Must remain true | Demonstration |
| --- | --- | --- |
| Declarative state | OS packages, services, mounts, policy and bundled desktop integrations come from Git | Dry-build of approved Git commit |
| Hardware evidence | Generated hardware configuration reflects the installed host, never invented during a refactor | Reinstall verify-hardware checks |
| Self-healing | Only bounded, deterministic, non-destructive repair; no autonomous disk, credential or filesystem changes | Failure-injection tests and supervised recovery drill |
| Release safety | Candidate can be built, diffed, test-activated, checked and rolled back without silent promotion | `helix-update` and systemd-boot recovery evidence |
| Known-good fallback | At least one previously qualified NixOS store closure stays protected from age-based garbage collection | Verify GC root and actual boot-menu accessibility |
| Boot independence | NAS, Pi-hole and sibling checkouts cannot gate the NixOS boot or the runtime promotion health gate | Boot/session with NAS unavailable |
| Recoverable state | Home, credentials, identity and important application state have explicit backup/restore paths | Recover sample files plus an actual restored application state |
| Independent recovery | A failure or compromise of the NAS cannot destroy every recovery copy | Real decryption from an approved independent destination |
| Truthful health | Reports distinguish responsive process, application readiness, last successful backup and tested restorability | Failure and staleness fixtures |
| Cost discipline | Idle, build, login, memory and storage overhead are measured before new complexity is accepted | `helix-benchmark` + closure/boot baseline |

## Recovery planes

1. **Runtime gate**: `helix-health --check` is fast and NAS-independent. Its
   sole purpose is deciding whether a candidate workstation generation is
   sufficiently alive to promote. It is not a recovery assurance report.
2. **Recovery readiness**: local backup freshness, retention, independent-copy
   age, restore-drill age, protected boot fallback and availability of external
   dependencies. A failed recovery audit must raise attention; it must never
   prevent Helix boot.
3. **Disaster recovery**: reviewed physical disk identity, approved Git commit,
   pinned Nixpkgs, separately retrievable credentials, verified backup set,
   explicit restore, and first-boot postflight. No destructive automation.

## What does not count as proof

- CI evaluation is not a successful production closure build.
- A full gate that substitutes CPU Ollama and disables arcade/emulation is not
  proof the real CUDA or emulation profile has run.
- `systemctl is-active` is not application readiness.
- A green TCP reachability pip is not an application health verdict.
- A recent backup's exit status is not a restore drill.
- A checksum on a plaintext NAS archive is integrity evidence, not encryption
  or protection against an attacker able to replace the checksum.
- A pinned Nix store closure is not necessarily a selectable bootloader entry.
- A simulated restoration is not an independently verified replacement host.

## Explicit failure scenarios

Before a release is described as disaster-ready, exercise these independently:

1. NAS offline at startup and after suspend: boot proceeds; local services
   work; missing external dependencies are visible without retry storms.
2. NAS disappears mid-backup: no false success, no write to the underlying
   unmounted local directory, no invisible permanent failure.
3. Candidate activation fails at test, health check, profile registration or
   final switch: previous boot selection and running configuration are
   preserved or a clear, truthful manual recovery route is emitted.
4. OS drive replacement: a clean checkout of an approved commit rebuilds on
   deliberately identified storage; secrets and app state restore; postflight
   passes. Test the non-destructive part in disposable media first.
5. Old data restored: recover a file deleted days or weeks earlier, not just
   last night's copy; verify real application data can be opened.
6. Backup host lost: prove an encrypted copy survives on independently
   administered storage and can be decrypted with a separately held identity.

## Existing limits requiring explicit acceptance

- As of 2026-11-21, the canonical reinstall tar sets on the NAS are
  unencrypted. They contain sensitive user state and machine identity.
- Reinstall restore currently assumes a mounted canonical Infernalnexus share;
  a complete NAS-free recovery workflow is not yet qualified.
- hamology Phase 1B provides opt-in tiered retention, sealed independent-copy
  artifacts and local restore drills; real off-NAS transport remains pending.
  hamology owns those artifacts, not Helix or the destination.
- The NVIDIA 620.70.06 production driver is qualified on this RTX 5080;
  its explicit pin does not update automatically. Upstream Xid109 remains
  an incident to monitor, not a reason to revert a working driver.
- The release target v0.3.0-alpha.8 must not be called tagged until an actual
  Git tag follows the documented local full gate.
- Local and private state (login tokens, passwords, editor settings, games,
  commissioned cooling profiles) is not wholly declarative. Each is either
  restored or deliberately re-initialised during recovery.

## Change acceptance

For any significant work, specify the owning layer, state affected, failure
mode introduced, verification performed, rollback, and which claims still
require Helix or real backup media. Keep PRs scoped. Neither a completed
build nor an agent's interpretation is permission to `switch`, partition,
wipe, delete backups, remove a fallback generation or regenerate secrets.
Document measured improvements, and reject speculative optimisations that
add a new privileged daemon or a second configuration authority.

The governing objective is not maximum automation; it is the shortest,
clearest, *proven* route from a failed machine to a working one.
