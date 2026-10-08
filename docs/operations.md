# Helix health and lifecycle

`helix-health` is a read-only, one-screen report covering NixOS/kernel and the
current generation, NVIDIA status, RAM/zram/swap, local disk space, failed system
and user units, OpenClaw gateway/version, monitoring services, and the selected
pinned Nixpkgs revision. Missing optional session data is
shown as a warning rather than aborting the report. `helix-health --check` is
the non-interactive runtime gate: it verifies the NVIDIA driver, GAMES_NVME, and
the critical SSH, Ollama, monitoring, cooling, and available user-session
OpenClaw services, returning nonzero on failure. Its unit list is generated from
`helix.health.criticalUnits` and `criticalUserUnits`, which each feature
appends to, so disabling a feature also removes it from the gate. Infernalnexus is deliberately
not part of this gate because NAS availability must not determine workstation
boot health.

`helix-update` is the deliberate attended update path. It only operates on
`/home/tristan/Projects/nixos-helix` on `main`, refuses any dirty or untracked
work tree, fast-forwards to reviewed `main`, runs `scripts/check.sh`, builds a
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
Nix builds run at idle CPU priority, so a large local build cannot make the
desktop, a game or a local model stutter.

OpenClaw comes from `openclaw/nix-openclaw` revision
`d3760a6f103642f11e24bc01ee9aec80a0153774`, fetched with a fixed unpacked hash.
Its first-party `nix/packages` definition pins stable OpenClaw 2026.7.1-2. The
configuration asserts a minimum of 2026.6.9, and retains Nix mode, loopback-only
network access, Ollama, secret-file handling, and the existing systemd sandbox.
Inside that sandbox the Helix checkout is writable, but `.git`, `.vscode`,
`.zed` and `.claude` are read-only because they configure commands that run as
`tristan` outside it. OpenClaw can edit tracked files; committing stays a
human step. `helix-update` also disables `core.fsmonitor` and hooks for its
Git commands.

## Failure alerts

Unattended units raise a critical desktop notification when they fail: the
nightly restic and hamology backups and weekly Nix GC and store optimisation.
`services/failure-alerts.nix` attaches `OnFailure=helix-failure-alert@%n` to
every unit in `helix.failureAlerts.units` or `userUnits`; each feature
registers its own, as for the health gate. The notification names the unit and
systemd's verdict (exit code, timeout, out of memory), quotes the end of the
failed run's own output and gives the `journalctl` command for details. It is
only sent to a notification server that is already running, so it never starts
one (mako would otherwise displace Plasma's). A
failure while nobody is logged in is reported at the next graphical login, and
at every login after that until the unit succeeds or the failure is
acknowledged:

```bash
systemctl reset-failed restic-backups-helix.service   # or systemctl --user ...
```

To see an alert without breaking anything:

```bash
sudo systemctl start helix-failure-alert@alert-test.service
```

## Nixpkgs pin

Nixpkgs is pinned in `nixpkgs.json` to an immutable NixOS release tarball and
its hash, so a commit fully determines the system that CI, rebuilds and
`helix-update` build, and any past generation can be rebuilt from its commit.
To update, run `./scripts/bump-nixpkgs.sh` (newest release of the series, or a
named release), check and dry-build, and open a pull request; after it merges,
`helix-update` applies it.

The `Nixpkgs bump` workflow does the first half every week (Sunday morning in
New Zealand, or on manual dispatch): it pins the newest release, runs
`check.sh --quick`, and opens or updates one pull request from
`automation/nixpkgs-bump` with a table of the versions that matter on Helix
(`scripts/nixpkgs-version-summary.sh`), including whether OpenClaw's Node and
the NVIDIA module will rebuild. Testing it on Helix, merging and switching stay
manual. A newer release closes that pull request as superseded and opens a fresh one,
unless it changes more than `nixpkgs.json` (someone's fix): that is never
overwritten or closed, and gets one comment instead. Closing it without
merging skips that release; the next one opens a new pull request. It needs **Settings → Actions → General → Allow GitHub Actions to
create and approve pull requests** enabled once; without it the run fails
visibly at the pull-request step.

Routine GitHub CI runs static checks and Nix evaluation/invariants against the
pinned Nixpkgs. It deliberately does not build the complete CUDA-enabled
workstation closure or compile MAME on every pull request.

The expensive closure checks live behind `scripts/check.sh --full`, which is
run on Helix before an alpha is tagged. Its closure uses CPU Ollama and leaves
out emulation and hamCade, but still includes OpenClaw's source-built Node.js
(see `packages/openclaw-gateway-npm.nix`), which no binary cache provides.
Helix builds it once and reuses it until one of its inputs changes, which a
Nixpkgs bump can do; a GitHub-hosted runner timed out compiling it, so the
`Release CI` workflow runs only on manual dispatch and no push or schedule
starts it.
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


## Central Netdata

Helix runs a loopback-only Netdata Agent as a streaming child of the Netdata parent on
infernalnexus at `192.168.1.8:19999`. The parent is Helix's only metrics history; the earlier
local Prometheus/Grafana stack was retired.

The child collects native host/process/filesystem/network/sensor metrics plus explicit NVIDIA,
SMART and systemd-unit jobs. Its local database is intentionally short-lived RAM storage; the NAS
parent owns persistent dbengine history and presents both `infernalnexus` and `helix` in one
LAN-local dashboard.

The stream API key is not part of the Nix store. `hamology-netdata-deploy --execute` installs the
shared UUID at `/var/lib/netdata/parent-api-key` with mode 0600. Before that file exists, the local
Netdata service still starts normally with outbound streaming disabled.

The Netdata web interface on Helix binds only to `127.0.0.1:19999`; port 19999 is not opened in
the workstation firewall. Use:

```bash
helix-monitor netdata
```

or the **Helix Monitor** launcher to open the central parent dashboard.
