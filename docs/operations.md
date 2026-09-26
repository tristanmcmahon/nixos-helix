# Helix health and lifecycle

`helix-health` is a read-only, one-screen report covering NixOS/kernel and the
current generation, NVIDIA status, RAM/zram/swap, local disk space, failed system
and user units, OpenClaw gateway/version, monitoring services, and the selected
root NixOS channel and its age where available. Missing optional session data is
shown as a warning rather than aborting the report. `helix-health --check` is
the non-interactive runtime gate: it verifies the NVIDIA driver, GAMES_NVME, and
the critical SSH, Ollama, monitoring, cooling, and available user-session
OpenClaw services, returning nonzero on failure. Infernalnexus is deliberately
not part of this gate because NAS availability must not determine workstation
boot health.

`helix-update` is the deliberate attended update path. It only operates on
`/home/tristan/Projects/nixos-helix`, refuses any dirty or untracked work tree,
updates only the root `nixos` channel, runs `scripts/check.sh`, builds a
candidate, displays `nvd diff`, and test-activates it. The candidate's own
`helix-health --check` must pass before it is registered in the system profile and
selected for boot; a failed health gate restores the previous running generation
and aborts the update.
It uses `nom` when present and retains raw build output during bootstrap. It
does not schedule or autonomously activate updates, and it does not run GC.

Helix uses native persistent weekly Nix GC with the existing one-hour randomized
delay and deletes generations older than 14 days. Store optimisation stays
weekly. The 32 GiB workstation uses zstd zram at 50% RAM and priority 100; no
disk swap is created. systemd-oomd watches root and user slices, not system.slice.

OpenClaw comes from `openclaw/nix-openclaw` revision
`d3760a6f103642f11e24bc01ee9aec80a0153774`, fetched with a fixed unpacked hash.
Its first-party `nix/packages` definition pins stable OpenClaw 2026.7.1-2. The
configuration asserts a minimum of 2026.6.9, and retains Nix mode, loopback-only
network access, Ollama, secret-file handling, and the existing systemd sandbox.

Routine GitHub CI runs static checks and Nix evaluation/invariants against the
NixOS 26.05 channel. It deliberately does not build the complete CUDA-enabled
workstation closure or compile MAME on every pull request.

The expensive closure checks live behind `scripts/check.sh --full` and the
`Release CI` workflow. Hosted Release CI is manual-dispatch only so release
branch maintenance cannot accidentally start a large workstation closure build.
It does not modify Helix.


## Git and repository hygiene

Helix keeps GitHub HTTPS authentication independent of Nix store generations.
The `helix-git-credential-helper` user service rewrites only the GitHub and Gist
host-specific credential helpers to:

```text
!gh auth git-credential
```

The command is PATH-resolved deliberately. Absolute helpers under
`/nix/store/.../gh.../.gh-wrapped` become invalid after those generations are
garbage-collected. Run `helix-git-credential-repair` manually at any time to
repair the same entries immediately; other Git configuration is left untouched.

Remote branch cleanup is explicit and safe-by-construction:

```bash
./scripts/prune-merged-branches.sh
./scripts/prune-merged-branches.sh --delete
```

The first command is a dry run. Deletion is limited to remote branches Git proves
are ancestors of `origin/main`; `main`, `release/*`, `rollback/*`, and open
pull-request heads are preserved. The delete path also enables GitHub's automatic
deletion of merged pull-request branches so the same clutter does not immediately
return. Diverged branches are never deleted by this tool and require deliberate
review.
