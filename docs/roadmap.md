# Evaluation and consolidation roadmap

Evaluated at `f065b9e` (the restored pre-morning baseline, identical to
`2cf357b`) on 2026-09-30. Nix was not available in the evaluation environment,
so Nix-level claims come from reading the modules; the Python fixtures,
`check-docs.py`, `check-modules.py` and `bash -n` were run and pass.

## Summary

Helix is in good shape for a single-host configuration. It has an explicit
ownership model, sibling-project boundaries, loopback-only services, fixed hashes on
every custom fetch, generated hardware evidence left untouched, and a tiered
check suite. The main costs now are **duplication** and **uneven patterns**
that grew while features were added quickly:

- the same host facts (user, home, repository path, disk IDs, NAS address,
  theme names, palettes, service lists) are written out in many files;
- the same rule is often tested in three places (Nix asserts, grep over the
  built closure, and regexes over docs);
- features are switched on in two different ways, and `packages/` and
  `profiles/` overlap;
- the Nixpkgs revision is not recorded anywhere, so a Git commit does not fully
  determine the system that CI or `helix-update` builds.

A few real defects were found as well. They are listed first because each is small
and independent.

## Defects

All five defects and the weekly Release CI schedule from Phase 0 were fixed on
2026-10-02. The `--full` gate still needs one confirming run.

1. **The `--full` release gate has failed since #74.**
   `scripts/checks/monitoring.sh:12` greps `helix-monitor --help` for
   `dashboard|fans|commission|…`, but #74 changed the usage string to
   `dashboard|netdata|fans|…`. Under `set -o pipefail` the full check exits
   there. Nobody noticed because Release CI is manual-only. Fix: match the new
   string, or better, check each subcommand name separately.

2. **The Ghostty profile choice is reset at every login.** `ghostty-profile`
   (Main/Moss/Slate/Ember, each with its own font) writes
   `~/.config/ghostty/profile.ghostty`. `helix-theme` writes the same file
   unconditionally (`desktop/theme.nix:103`), and it runs at every Plasma
   login (`random`) and in every graphical session (`--apply-current`). A
   Moss/Slate/Ember choice therefore lasts only until the next login, and the
   font always returns to JetBrains Mono. `docs/theme.md` describes the two
   systems as independent.

3. **The OpenClaw sandbox can write the repository's `.git` and editor config.**
   `services/openclaw.nix:111` binds `~/Projects/nixos-helix` read-write. Files
   such as `.git/config` (`core.fsmonitor`, `core.hooksPath`), `.git/hooks/*`
   and `.vscode/settings.json` (`nix.serverPath`) run commands as `tristan`
   *outside* the sandbox. `helix-update` runs `git status` in that checkout,
   which runs `core.fsmonitor`. Its clean-tree guard does not see untracked
   `.git` contents. Fix: keep the bind but add `.git`, `.vscode` and `.zed` to
   `ReadOnlyPaths`, or give the agent its own clone and pull reviewed changes
   from it.

4. **`helix-update` leaves the channel advanced when it fails.**
   `scripts/helix-update.sh:18` runs `nix-channel --update` before validation.
   A failed check or build leaves the new channel selected for the next manual
   rebuild. The script also builds with the ambient `NIX_PATH` instead of
   sourcing `release-environment.sh` as the other entry points do. Fix: run
   `nix-channel --rollback` from an error trap, and source the release
   environment. Phase 5 removes the problem entirely.

5. **Documentation drift.**
   - `docs/installation.md:46` says GC keeps 30 days; the configuration keeps 14.
   - `docs/profiles.md` lists the base set without `nix-output-monitor` and
     `nvd`, which `packages/base.nix` installs.
   - `docs/local-development.md` says the default suite "builds the canonical
     configuration"; only `--full` builds.
   - `services/openclaw.nix:49` says the NAS "is independently mounted
     read-only". Only the ROM share is; `nas1` is read-write, and only
     OpenClaw's view of it is read-only.
   - `scripts/report-minimality.sh` has a stale listener list (no monitoring
     services), an incomplete pin list, and calls `rg`, which is not in `shell.nix`.

## Duplication inventory

| Fact | Copies | Where |
| --- | --- | --- |
| User name / home | `/home/tristan` in 17 files | modules, systemd units, scripts, tests |
| Canonical checkout path | 7 files | `helix-update`, reinstall scripts, `openclaw.nix` |
| Infernalnexus address | 11 files | `monitoring.nix:13` bypasses `config/infernalnexus.nix` |
| Theme names | 5 lists in `desktop/theme.nix`, plus generator and checks | `themes`, `describe`, two `case` patterns, `random` pool |
| Palettes | 6 places | `palette.nix` (Fern only), generator `PALETTES`, Fern templates, Ghostty profiles, OSC strings in `ghostty.nix`, Hyprland borders |
| Critical service list | 4 places | `helix-health` (twice), `helix-monitor status`, `checks/monitoring.sh` |
| CIFS mount unit | 2 near-identical definitions | `system/nas.nix`, `profiles/emulation/storage.nix` |
| Mounted-directory initialiser | 6 near-identical units | `system/storage.nix` |
| Disk UUIDs and serials | 3 places | `system/storage.nix`, `local-ssds.nix`, `check-install-storage.sh` |
| Ollama model list | 4 places | module, invariants, `applications.sh`, docs (kept in step by regex) |
| OpenClaw version floor | 3 places | `configuration.nix`, `tests/invariants/core.nix` (floor and exact) |
| Everyday CLI tools | 2 package sets | `ripgrep`, `fd`, `bat` in both workstation and development |

## Uneven patterns

- **Two toggle models.** Emulation, hamCade, monitoring and Pi-hole use
  `helix.*.enable` options. Workstation, development, gaming and local LLM are
  switched by editing the import list. Only the option-based ones can be
  tested as disabled.
- **`packages/` versus `profiles/`.** The development and workstation
  profiles are pure wrappers around package modules. `packages/` mixes NixOS modules (package lists)
  with `callPackage` derivations.
- **Dormant code.** `packages/chatgpt.nix` is kept "for investigation", but its
  source URL is `…/latest/chatgpt_amd64.deb` with a fixed hash, so it breaks
  on the next upstream release. It needs special cases in `check-modules.py`
  and two negative assertions.
- **Two monitoring stacks.** Prometheus, Grafana and three exporters keep 400
  days locally. Netdata collects much of the same data (node, NVIDIA, SMART)
  and streams it to the NAS parent, which keeps persistent history.
- **Second Nixpkgs for arcade.** `vendor/hamcade/dependencies.nix` imports a
  whole second Nixpkgs for MAME, while `chdtools` uses `pkgs.mame.tools` from
  the main set, so two MAME builds are in play. This belongs to hamCade and
  should be raised there.
- **Vendored snapshots** use three different provenance formats: a
  `PROVENANCE.md`, a header comment, and a comment in the consuming module.
- **Many ways to launch Fuzzel.** The Hyprland menu uses the current theme,
  but the exit prompt and Ghostty choosers use `/etc/helix/theme/fuzzel.ini`,
  which is always Fern.

## Test and CI observations

- `--full` evaluates the whole system about ten separate times
  (`import <nixpkgs/nixos>` in the checks and tests), plus the build itself.
- The 219 Nix `assert`s stop at the first failure and report only a line number.
- Many assertions restate the implementation (`zramSwap.memoryPercent == 50`,
  exact model lists, exact option strings). `docs/architecture.md` says tests
  should not do this. Policy assertions carry the value: loopback-only
  listeners, the firewall port set, SSH authentication, the NAS absent from
  fstab, and removed features staying absent.
- About 124 closure checks are `grep`/`[[ ]]` lines. Many repeat evaluation
  invariants against built unit files.
- `test-reinstall-safety.sh` greps the backup script for literal source lines.
  That locks in the wording, not the behaviour; `test-reinstall-restore.sh`
  already shows the behavioural approach.
- CI evaluates against `channel:nixos-26.05`, which moves over time. Helix
  builds from the root channel, which also moves, and not in lockstep.
- `git diff --check` does nothing on a clean CI checkout. The Nix formatting
  loop could be `nixfmt --check`.

## Roadmap

Each phase lands as small pull requests that keep `check.sh` green, and none
changes runtime behaviour unless stated.

### Phase 0: defects (days)

1. Fix the monitoring usage grep and run `check.sh --full` once to confirm the
   release gate passes end to end.
2. Make `.git`, `.vscode` and `.zed` read-only inside the OpenClaw sandbox, and
   add a closure check that asserts it.
3. Add channel rollback on failure to `helix-update` and source
   `release-environment.sh` in it.
4. Resolve Ghostty ownership (see Phase 3; the interim fix is for
   `helix-theme` not to overwrite a non-Main profile).
5. Correct the documentation drift listed above.
6. Add a weekly `schedule:` trigger to Release CI so breakage like defect 1
   shows up within a week. Keep `workflow_dispatch`.

### Phase 1: one source for host facts

- Add `config/helix.nix` beside `config/infernalnexus.nix` holding the user,
  home, canonical checkout, GAMES_NVME UUID/serial and mount point, and the SSD
  list (absorbing `system/local-ssds.nix`). Nix modules and tests import it.
  Scripts receive it through `writeShellApplication` substitutions, or through
  `nix-instantiate --eval` when they run from the checkout.
- Model shares in `config/infernalnexus.nix` with a `readOnly` flag and
  generate the mount and automount units from a single helper. `nas.nix` and
  `emulation/storage.nix` then only choose which shares they enable.
- Add a small `lib/` with:
  - `mkMountedDirectory { mount, path, owner, group, mode }`, replacing the six
    initialiser units;
  - `mkUserOneshot`, for the repeated `ConditionUser` / `HOME` /
    `XDG_CONFIG_HOME` boilerplate.
- Use `infernalnexus.host` in `monitoring.nix` for the Netdata URL.

### Phase 2: uniform features and module layout

- Give every profile a `helix.<feature>.enable` option. Import all modules
  unconditionally from one list, and let `configuration.nix` only set options.
  The "disabled" tests then become one generic test that, for each feature,
  disables it and asserts its packages, units and ports disappear.
- Fold each `packages/<set>.nix` module into its profile. Leave `packages/`
  holding only derivations: `gridplayer`, `zen-browser`, `hamllm`, and the
  OpenClaw overlay.
- Remove `packages/chatgpt.nix` (Git history keeps it), its `check-modules.py`
  special case, and its negative assertions.
- Remove duplicate package entries. Keep one process monitor unless several
  are wanted on purpose (`htop`, `btop` and `bottom` are all installed,
  alongside `nvtop` for the GPU).
- Emulation should depend on the gaming option instead of re-declaring 32-bit
  graphics and audio. Its existing assertion already enforces this.

### Phase 3: theme pipeline

- Put all seven palettes, including `hotdog` and Fern, in one
  `config/theme/palettes.nix`, each with a name, description, a
  `randomEligible` flag and colour roles. Derive `themes`, the CLI's `case`
  patterns, `describe` and the random pool from it.
- Replace hex substitution in `generate-theme-family.py` with named
  placeholders (`@surface@`, `@accent@`, …) in the Fern templates, rendered
  from JSON that Nix produces. The current approach silently rewrites any value
  that happens to equal a Fern colour.
- Split Ghostty into two files included from `config.ghostty`: `theme.ghostty`
  for colours, owned by `helix-theme`, and `font.ghostty` for the typeface,
  owned by `ghostty-profile`. Generate the surface-profile OSC strings from the
  same palette data instead of hand-writing them.
- Use one current-theme Fuzzel config everywhere, and take the Hyprland border
  colours from the palette.

### Phase 4: tests and CI

- Add a root `default.nix` that evaluates the configuration once and exposes
  `system`, `hyprlandConfig`, `sessionData`, the 1Password packages, and a
  `checks` attribute set. The shell checks then use `nix-build -A …` in a
  single invocation.
- Replace chained `assert`s with a list of `{ name; ok; }` invariants and a
  reporter that prints every failure by name.
- Prune assertions that only mirror implementation. Keep the policy set, and
  keep the regression tests tied to real incidents.
- Add a `helix.health.criticalUnits` option that each module appends to.
  Generate the `helix-health --check` list, `helix-monitor status` and the
  closure checks from it, so disabling monitoring no longer fails the health
  gate.
- Replace source-grepping in `test-reinstall-safety.sh` with behavioural tests
  in the style of `test-reinstall-restore.sh`.

### Phase 5: reproducible Nixpkgs (decision required)

Pin Nixpkgs in the repository without flakes, for example with `npins` or a
`nixpkgs.json` read by `fetchTarball`. `release-environment.sh` is already the
single place where Nixpkgs is chosen, so the change is contained:

- `release-environment.sh` resolves the pin instead of the root channel;
- CI uses the same pin, so a green PR means the exact system that will be built;
- `helix-update` becomes "bump the pin in a PR, check, build, diff, test,
  switch". Updates become reviewable diffs, and any past generation can be
  rebuilt from its commit.
- `nix.nixPath` points at the pin, so ad-hoc `nix-shell` use matches the system.

This reverses the documented "root channel" choice, so it needs an explicit
decision.

### Phase 6: operations

- Declarative backups: add `services.restic.backups` (or borg) to the NAS for
  the home directory, `/etc/nixos/secrets`, SSH host keys and the
  NetworkManager profile, with a documented restore drill. Reinstall backups
  are currently one-shot and manual.
- Move the reinstall suite (about 2,000 lines across nine scripts) into
  `scripts/reinstall/` behind one `helix-reinstall
  {preflight,backup,restore,postflight,check-storage}` entry point. It stays
  for disaster recovery but leaves the everyday script list.
- Move per-release notes (`docs/alpha-5.md`) into a `CHANGELOG.md` or GitHub
  releases, and keep `docs/` for operating guides.
- Add a `scripts/vendor-sync` helper and one `PROVENANCE.md` format for all
  three vendored snapshots.
- Optional: narrow `allowUnfree` to an `allowUnfreePredicate` list, so each new
  unfree package is a deliberate choice.

## Decisions needed

- **Nixpkgs pinning (Phase 5).** Recommended. It is the largest
  reproducibility gain and fits the existing `release-environment.sh` seam.
- **Monitoring.** Keep both stacks, or retire local Prometheus/Grafana if the
  Netdata parent's retention covers the 400-day hardware history.
  CoolerControl is unaffected either way.
- **Hyprland.** If the session is rarely used, removing it removes the Waybar,
  Mako, Fuzzel and swaybg assets from the theme pipeline and several checks.
- **OpenClaw repository access.** Read-only metadata (recommended) or a
  separate agent clone.
- **`gzdoom` and `uzdoom`.** Keep both, or only the successor fork.
