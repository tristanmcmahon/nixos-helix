# Working on Helix

Helix is one NixOS 26.05 workstation configured declaratively with ordinary
NixOS modules and the Nixpkgs release pinned in `nixpkgs.json` (bump it with
`scripts/bump-nixpkgs.sh`, in a PR). There are no flakes, no Home
Manager and no host framework. Read `docs/architecture.md` and `docs/survivability-contract.md` before
structural changes; they are the authority on ownership, recovery guarantees,
state, safety, and network rules.

## Rules

- Never edit or reformat `hardware-configuration.nix`; it is generated evidence.
- Never change `system.stateVersion` (`release.nix`); 26.05 is permanent.
- `configuration.nix` stays boring: imports, `helix.*` enables, assertions.
  Packages go in `packages/`; profiles compose packages plus policy.
- Services are loopback-only unless deliberately exposed. SSH is the only
  intended firewall opening.
- Infernalnexus (the NAS) is optional: nothing may make boot or
  `helix-health --check` depend on it. Disk mounts use `nofail`, and
  initialisers check `ConditionPathIsMountPoint` before touching a disk.
- Sibling projects (hamCade, hamSteam, hamology, hamFence, hamKeyDist) own their
  own policy. Helix holds thin adapters only; never duplicate their authority.
- No secrets, tokens, passwords or keys in Git or the Nix store. Per-user state
  (logins, `~/.claude`, `~/.codex`, editor settings) stays mutable.
- Never write `/nix/store/...` paths into mutable user configuration. They
  break after garbage collection; use PATH-resolved commands.
- Automation may only repair what is deterministic, bounded and
  non-destructive. Partitioning, formatting, hardware identity and secret
  recovery need explicit human approval.
- Pin every custom fetch with a fixed hash and record it in
  `docs/custom-packages.md`.
- Add an invariant under `tests/invariants/` when an incident reveals a durable
  rule, not to mirror implementation details. Keep docs in step: `check-docs.py`
  verifies some cross-file facts.

## Runtime safety gate — 2026-11-27 Steam incident

- **The ability to use the workstation is a hard invariant.** Game launch,
  window display, inputs and Steam startup outrank optional instrumentation,
  including FPS logging, monitoring, and convenience features.
- Classify changes to Steam/Proton startup, wrapper or FHS environments,
  `LD_PRELOAD`, `LD_LIBRARY_PATH`, `XDG_DATA_DIRS`, Vulkan layers,
  `STEAM_GAME_LAUNCH_SHELL`, `extraProfile`, `extraBwrapArgs`, and
  other game-launch hooks as **runtime-critical**.
- For runtime-critical changes, CI, Nix evaluation, a full closure build,
  a clean `helix-health --check`, and an apparently successful activation
  are **not** evidence that games launch. No merge or release based solely
  on those checks. Keep experiments on a branch; require the owner's
  explicit permission for an isolated, reversible live test on Helix.
- Before promoting such a change to `main`, record evidence from the
  candidate itself: Steam starts; Noita starts **and displays a window**;
  Tekken 7 and/or Space Marine 2 launch; existing Vulkan FPS recording
  still produces a fresh CSV. For claimed automatic OpenGL support,
  verify a new Noita CSV with **no per-game override**. Distinguish tested
  cases from untested claims and preserve the old configuration for rollback.
  Never substitute a sample from a different generation or a manual
  `mangohud %command%` launch for automatic acceptance.
- Never edit users' game launch options, bypass hamSteam, or introduce
  Steam-wide loader preloads or game-launch overrides as a speculative
  fix. Such mechanisms are not qualified by static checks and must not
  enter `main` without the complete runtime evidence and owner approval.
- At the first launch/display regression, stop. Restore the known-good
  generation, restart/reboot as needed, and verify that games work.
  Revert dangerous code from `main` before any future update; do not
  stack further unqualified fixes on a broken baseline.
- If a safe implementation is not demonstrated, leave the feature
  incomplete. OpenGL recording is optional; working games are not.
  See `docs/mangohud-incident-2026-11-27.md`.

## Validation

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'   # static checks + evaluation + invariants
./scripts/rebuild.sh dry-build                       # build the candidate
./scripts/dev-shell.sh --run './scripts/check.sh --full'   # release gate (builds the system closure)
```

Activation is always the user's explicit decision. Do not run
`./scripts/rebuild.sh test` or `switch` (or `nixos-rebuild`, garbage collection,
or Nixpkgs pin bumps) unless asked. After a requested `test`, run
`helix-health --check`. Evaluation and builds do not prove hardware works; see
`docs/hardware-validation.md`.

## Working loop

Before handing work back, iterate without being asked:

1. Implement the change.
2. Validate: `check.sh`, evaluation, and builds of the touched packages.
3. Review your own diff adversarially (`/code-review` at high effort):
   correctness, regressions, stale checks or docs, simpler alternatives.
4. Fix what the review finds and validate again. Measure claimed gains and
   revert changes that do not earn their complexity. Repeat until a pass
   finds nothing worth changing.
5. Hand back once: what changed, what was verified and how, what only Helix
   can verify (with the exact command), and anything still uncertain.

## Conventions

- Nix is formatted with `nixfmt` and linted with `deadnix` and `statix`. Shell
  is `shellcheck`-clean and uses `set -euo pipefail`.
- Comments explain why, in full sentences, matching the surrounding modules.
- Work on a branch and open a pull request; `main` changes through PRs.
