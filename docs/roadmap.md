# Evaluation and consolidation roadmap

First evaluated at `f065b9e` on 2026-09-30. Re-evaluated on 2026-10-20 after
Phases 0, 1, 2, 3, 5 and 6 landed (#85–#103) and Hyprland was removed. Phase 4
(tests and CI) is the only phase still open.

## Summary

Helix has an explicit ownership model, sibling-project boundaries,
loopback-only services, fixed hashes on every custom fetch, generated
hardware evidence left untouched, a tiered check suite, and a pinned,
reproducible Nixpkgs (`nixpkgs.json`, bumped by a weekly automated PR). The
defects, duplication and uneven patterns found in the first pass are fixed;
see `CHANGELOG.md` for what shipped in each PR rather than re-deriving it
here. What remains is narrower:

- `--full` still evaluates the configuration 7 separate times
  (`import <nixpkgs/nixos>` across `scripts/` and `tests/`), each from a cold
  evaluation.
- 220 Nix `assert`s across `tests/invariants/` and `tests/*.nix` still stop at
  the first failure and report only a line number, not a name.
- Most assertions are now policy (loopback-only listeners, firewall ports,
  SSH authentication, the NAS absent from `fstab`, removed features staying
  absent), but some still restate implementation incidentally rather than
  guarding a durable rule. Only one has been pruned so far (the exact
  OpenClaw version pin in `tests/invariants/core.nix`, which duplicated the
  floor assertion `configuration.nix` already carries); a full pass has not
  been done.
- `vendor/hamcade/dependencies.nix` imports a second Nixpkgs for MAME while
  `chdtools` uses `pkgs.mame.tools` from the main set. This is hamCade's
  decision, not Helix's; raised there, not tracked further here.

## Resolved since the first pass

- **Phase 0 (defects).** All five fixed; `--full` has passed end to end on
  Helix since #94.
- **Phase 1 (host facts).** `config/helix.nix` and `lib/helix.nix`
  (`mkMountedDirectory`, `mkInfernalnexusShare`) centralise what used to be
  copied across 17+ files.
- **Phase 2 (uniform features).** Every profile (`workstation`,
  `development`, `gaming`, `emulation`, `hamCade`, `localLlm`) now exposes a
  `helix.<feature>.enable` option; `packages/` holds only derivations
  (`base`, `gridplayer`, `hamllm`, `helix-menu`, `helix-theme-family`, the
  OpenClaw overlay) rather than a mix of package-list modules and
  derivations. `packages/chatgpt.nix` and the duplicate process monitors
  (`htop`, `btop`) are gone; `bottom` and `nvtop` remain, one each.
- **Phase 3 (theme pipeline).** All seven palettes live in one
  `config/theme/palettes.nix`; `helix-theme`'s list, accepted names and
  random pool derive from it.
- **Phase 5 (reproducible Nixpkgs).** `nixpkgs.json` pins the release;
  `release-environment.sh` resolves it everywhere (CI, `rebuild.sh`,
  `helix-update`), and a weekly workflow proposes the next pin as its own PR.
- **Phase 6 (operations).** Declarative restic backups, a unified
  `helix-reinstall` entry point, `CHANGELOG.md`, and `vendor/sources.json`
  with `scripts/vendor-sync.sh` as the single provenance record (one format,
  not three) are all in place. `allowUnfree` was narrowed to an explicit
  `allowUnfreePredicate` list.
- **Monitoring decision.** Local Prometheus/Grafana was retired in favour of
  the Infernalnexus Netdata parent; CoolerControl is unaffected.
- **OpenClaw repository access decision.** `.git`, `.vscode` and `.zed` are
  `ReadOnlyPaths` inside the sandbox, so the agent can read but not run
  commands via those files.
- **Hyprland decision.** Removed on 2026-10-20: it was never used, and an
  optional second session was pure maintenance cost (its own theme startup
  helper, exit prompt, Waybar/Mako/Fuzzel/swaybg assets, and three closure
  checks). Plasma is now the only session. Recoverable from Git history
  (`desktop/hyprland.nix` as of this commit's parent) if ever wanted again.
- **Plasma performance.** Since Hyprland is gone, Plasma's own session now
  carries an explicit performance baseline, force-written every login by
  `desktop/theme.nix`: animations off (`AnimationDurationFactor=0`), no splash
  screen, the Blur compositor effect off, KWin
  tearing allowed (benefits fullscreen Steam/gamescope), and Baloo file
  indexing disabled (`balooctl6 disable`). See
  `docs/hardware-validation.md`'s "Plasma performance" section for the manual
  verification steps a build cannot cover.

## Remaining: Phase 4 (tests and CI)

- Add a root `default.nix` that evaluates the configuration once and exposes
  `system`, `sessionData`, the 1Password packages, and a `checks` attribute
  set, so the 7 separate evaluations become one. The shell checks then use
  `nix-build -A …` against that single evaluation.
- Replace chained `assert`s with a list of `{ name; ok; }` invariants and a
  reporter that prints every failure by name, not just the first assert's
  line number.
- Finish pruning assertions that only mirror implementation incidentally
  (one removed so far; a full pass across the 220 remaining has not been
  done). Keep the policy set, and keep regression tests tied to real
  incidents, per `docs/architecture.md`.
- Add a `helix.health.criticalUnits` option that each module appends to.
  Generate the `helix-health --check` list, `helix-monitor status` and the
  closure checks from it, so disabling a feature no longer requires updating
  the health gate by hand.
- Replace source-grepping in `test-reinstall-safety.sh` with behavioural
  tests in the style of `test-reinstall-restore.sh`.

## Decisions needed

- **`gzdoom` and `uzdoom`.** Both are still installed. Keep both, or only the
  successor fork.
- **NVIDIA Xid 109 (`CTX SWITCH TIMEOUT`) under sustained Proton load.**
  Unresolved; needs real investigation in this repo, not another per-game
  workaround. `journalctl | grep "Xid (PCI"` shows 15 occurrences across 6
  separate boots between 2026-10-07 and 2026-11-07, every one traced by PID
  to either STAR WARS: Galactic Racer (appid 4078430) or Warhammer 40,000:
  Space Marine 2 (appid 2183900) — see `docs/profiles.md`. One occurrence
  (2026-10-07 21:18, boot `920bbe2b`) recurred within two minutes of a fresh
  reboot taken specifically to clear the first one that same evening, so a
  reboot alone does not fix it. This spans two unrelated engines (Unreal 5
  vs Saber's own Swarm engine), two unrelated anti-cheat/online stacks (Epic
  Online Services vs EasyAntiCheat), and three unrelated Proton builds
  (Proton Experimental, Proton Hotfix and GE-Proton11-9 have all hit it on
  Galactic Racer alone on different days) — ruling out a per-game, per-engine
  or per-Proton-build cause. Every hit leaves the process, audio and GPU
  submission alive — the GPU stays non-idle and the game keeps running —
  but drawing stops permanently for that session: Space Marine 2's own menus
  render fine first, so whatever triggers it is a specific heavy workload
  partway into a session, not startup itself.

  `hardware/nvidia.nix` runs the RTX 5080 (Blackwell) on NVIDIA's open
  kernel modules (`open = true`) at the nixpkgs-stable driver pin (595.71.05
  per `CHANGELOG.md`); Blackwell plus open kernel modules has a documented
  history of scheduling instability elsewhere, which is the leading
  hypothesis. Tried and confirmed **not** the cause on Galactic Racer:
  `PROTON_ENABLE_NVAPI=0`; forcing ray tracing off
  (`-noraytracing -execcmds="r.RayTracing 0"`). Confirmed working on Windows
  on the same physical hardware, which points at the Linux driver stack
  specifically rather than a hardware fault, though that is not conclusive
  on its own.

  Not yet tried, roughly in order of how much they'd narrow it down:
  1. Whether a **native (non-Proton) Vulkan workload** can reproduce it —
     this is the single biggest open question, since every occurrence so far
     ran through Proton/Wine. `helix-benchmark gpu` (`vkmark`) is one
     candidate; so is Steam's own `fossilize_replay`, which already runs
     natively (no Wine involved) during every post-session shader-cache
     write-back and submits a comparable burst of Vulkan pipeline work. If a
     native workload reproduces the Xid, Proton/Wine/EOS/EAC are all cleared
     and this becomes a pure driver/GPU question; if it never does, the
     translation layer itself is implicated.
  2. **Capture GPU state live through a reproduction** (`nvidia-smi -l 1`
     logging temperature/clocks/power, or a persistent `journalctl -f`
     watch) — none of the existing evidence includes this, only the Xid line
     itself after the fact.
  3. Check NVIDIA's 595.x release notes for a documented Blackwell Xid 109
     fix before changing anything.
  4. `open = false` (proprietary kernel modules) as a controlled A/B test —
     easy to try, but confounds with (1) and (3) if done first; the open
     module choice in `hardware/nvidia.nix` currently has a comment
     asserting it is required for this PCI family, so verify that is still
     accurate for the current driver before flipping it.
  5. A different driver branch/version.

  Change exactly one variable at a time and reproduce (or fail to) before
  trying the next, or a fix cannot be attributed. `docs/profiles.md` must be
  corrected to stop recommending GE-Proton for Galactic Racer if this is
  ever actually fixed — right now it correctly says not to.
