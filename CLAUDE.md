# Working on Helix

Helix is one NixOS 26.05 workstation configured declaratively with ordinary
NixOS modules and the Nixpkgs release pinned in `nixpkgs.json` (bump it with
`scripts/bump-nixpkgs.sh`, in a PR). There are no flakes, no Home
Manager and no host framework. Read `docs/architecture.md` before structural
changes; it is the authority on ownership, state, safety and network rules.

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

## Validation

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'   # static checks + evaluation + invariants
./scripts/rebuild.sh dry-build                       # build the candidate
./scripts/dev-shell.sh --run './scripts/check.sh --full'   # release gate (CUDA/MAME closures)
```

Activation is always the user's explicit decision. Do not run
`./scripts/rebuild.sh test` or `switch` (or `nixos-rebuild`, garbage collection,
or Nixpkgs pin bumps) unless asked. After a requested `test`, run
`helix-health --check`. Evaluation and builds do not prove hardware works; see
`docs/hardware-validation.md`.

## Conventions

- Nix is formatted with `nixfmt` and linted with `deadnix` and `statix`. Shell
  is `shellcheck`-clean and uses `set -euo pipefail`.
- Comments explain why, in full sentences, matching the surrounding modules.
- Work on a branch and open a pull request; `main` changes through PRs.
