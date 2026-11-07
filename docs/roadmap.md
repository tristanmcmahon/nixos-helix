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
- **Nightly backups after a suspend resume.** Fixed properly in #109: both
  backup units run `helix-wait-for-nas` (up to three minutes for the NAS's SMB
  port, non-fatal if it never answers) and deliberately never restart on
  failure, with an invariant holding both properties. An earlier attempt at
  this (commit `ae658dd`, "Retry nightly backups...") used
  `Restart=on-failure`, which #109's review correctly rejected: a systemd
  start-limit counts starts, not run time, so a slow failure (an SSH attempt
  to a NAS that is down) could retry forever without ever reaching the limit
  or raising its alert. That commit reached `claude/intelligent-hamilton-g61kbz`
  after #106 was already squash-merged, so it never reached `main`; `a199405`
  then landed its `CHANGELOG.md` text without its code, so `main` briefly
  documented a fix it didn't contain. #109 corrected both the code and the
  changelog entry.
- **NAS mount permanently latching on a transient network blip.** #109
  deliberately left the mount's own start-limit unchanged, pending a failure
  log from Helix. That log arrived on 2026-10-30: `mnt-infernalnexus-nas1.mount`
  hit the default start-limit (5 attempts/10s) during a burst of
  "Network is unreachable" errors, and both it and its automount latched
  `failed`/`mount-start-limit-hit` and did not self-recover; the share stayed
  unmounted for about 20 hours until a manual `systemctl reset-failed` +
  `start`. `lib/helix.nix`'s `mkInfernalnexusShare` now sets
  `unitConfig.StartLimitIntervalSec = 0` on the mount (shared by `nas1` and
  `roms`), so it retries indefinitely instead of ever latching. (An earlier,
  weaker attempt at this — widening the limit to 2 minutes/10 attempts rather
  than removing it — was made and validated in this same session but never
  actually landed in a commit; it does not appear in `main`'s history.)
- **Netdata polling a BMC that doesn't exist.** `freeipmi` is now disabled in
  `services/netdata.nix`; it was logging kernel warnings for about ten minutes
  every boot before giving up on its own.

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
  workaround. Recurred again on 2026-11-07 at 15:42:44, 35 seconds into
  STAR WARS: Galactic Racer on Proton Experimental (`chdir` to the game's
  install dir logged at 15:42:09) — on a fresh boot, 3 minutes after reboot,
  so it is not specific to a stale session. `journalctl | grep "Xid (PCI"`
  shows 16 occurrences across 7 separate boots between 2026-10-07 and
  2026-11-07, every one traced by PID
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

  1. **Native (non-Proton) Vulkan workload, attempted on 2026-11-07: did
     not reproduce it.** `vkmark --present-mode immediate --run-forever` ran
     for a full 10 minutes (confirmed real this time by its own `timeout`
     wrapper exiting 124, not instantly; the first attempt the same day used
     a bare `vkmark` with no store path and never actually ran — see
     `CHANGELOG.md`/git history), with `nvidia-smi -l 1` telemetry logging
     throughout. No Xid, no thermal or clock anomaly (peaked at 57°C). This
     is one data point, not conclusive on its own: vkmark's workload is a
     simpler, more repetitive scene set than Unreal 5 or Saber's Swarm
     engine under Proton, so it does not rule out that some native workload
     could still trigger it, only that this particular one did not in this
     window. It does shift weight slightly toward the translation layer
     (Proton/Wine/EOS/EAC) over a pure driver/GPU fault.

     **Second native attempt, same day: also did not reproduce it, but with
     real caveats.** `fossilize_replay` (native, part of the Steam Linux
     Runtime, run through `steam-run` since it is a generic dynamically-linked
     binary NixOS cannot exec directly) replayed Galactic Racer's own 936 MB
     captured pipeline cache
     (`steamapps/shadercache/4078430/fozpipelinesv6/steamapprun_pipeline_cache.3554f158047e28bf/steam_pipeline_cache.foz`)
     for a full 10 minutes (confirmed real: genuine GPU utilization throughout,
     `timeout` exited 124). No Xid; GPU stayed cooler than the vkmark run
     (49°C peak vs. 57°C), consistent with pipeline-compilation-bound work
     rather than sustained rendering. Two caveats keep this from being a
     clean "native" result: the replayed pipelines were originally captured
     from a **Proton/vkd3d session** (`engineName: vkd3d`,
     `applicationName: EOSOverlayRenderer-Win64-Shipping.exe` — vkd3d is the
     DX12-to-Vulkan layer Proton uses for Unreal 5's DX12 path), so this is
     native *execution* of Proton-originated data, not a Proton-untouched
     pipeline; and several blobs failed to parse (`Failed to parse pNext
     chain for sType: 1000574000`, an unrecognized extension struct) and were
     silently skipped, so this did not exercise 100% of the cache.

     Two independent native attempts now agree (neither reproduced it), which
     is worth more than either alone, but both have real caveats (a simpler
     synthetic workload; a partial replay of Proton-originated data) that
     keep "native vs. Proton" from being settled. Remaining native candidate:
     a from-scratch native Vulkan/DX12 title with no Proton involvement at
     any point (e.g. a native Linux game using a similar engine), which
     neither attempt here actually is.
  2. **Capture GPU state live through a reproduction under Proton** — done
     alongside (1) only for the non-reproducing native case; still not done
     for an actual Galactic Racer/Space Marine 2 hang. Every existing hang
     data point is still only the Xid line itself after the fact, with no
     temperature/clock/power trace leading into it.
  3. **Checked NVIDIA's 595.x release notes on 2026-11-08: this is a known,
     NVIDIA-acknowledged bug, not something to wait on a future driver
     for.** `NVIDIA/open-gpu-kernel-modules#1097` (GitHub) describes the
     identical symptom — Xid 109 CTX SWITCH TIMEOUT on Blackwell
     (RTX 5090/5080/5070 Ti/5060 Ti) under Proton, confirmed across driver
     595.58.03 through at least 615.78.08 — and NVIDIA has assigned it
     internal bug **6017526**. The 595.71.05 release notes themselves list
     exactly one fix (an unrelated Wayland suspend/resume rendering bug), so
     this was never silently fixed in the version Helix is pinned to. Root
     cause per the issue and corroborating reports (vkd3d-proton
     `HansKristian-Work/vkd3d-proton#2914`, CachyOS forum): **descriptor
     heap exhaustion** in vkd3d-proton's classic code path on Blackwell —
     which is also consistent with (1)'s native results, since neither
     vkmark nor fossilize_replay exercises live DX12 descriptor-heap
     allocation the way actual gameplay does.

     **Tried on 2026-11-08: `VKD3D_CONFIG=descriptor_heap %command%` on
     Galactic Racer (Proton Experimental) did not prevent it.** Hit the
     identical Xid 109 again at 10:42:06, ~1 minute into the session,
     visually confirmed (audio kept playing, screen went to the clear
     colour) while watched live. This is the first occurrence with a GPU
     telemetry trace leading into it (`nvidia-smi -l 1`, logged throughout
     via a persistent journal watch): utilization was low and bursty
     (7–40%) for the preceding ~50 seconds, then at 10:42:03 — 3 seconds
     before the Xid — utilization jumped to and pegged at 100%, clocks
     locked at max boost (2917 MHz), while power draw stayed at only
     48–60 W, far below what genuine 100%-utilization work on this card
     draws (200–300 W+). High reported utilization with anomalously low
     power is consistent with the GPU spinning on an already-wedged context
     switch for a few seconds before the driver's watchdog gives up and
     logs the Xid, rather than a sudden failure with no warning.

     This does not clear descriptor heap exhaustion as the cause: the
     launch option only has an effect if Proton Experimental's bundled
     vkd3d-proton actually implements `VK_EXT_descriptor_heap` (PR #2805) —
     not yet confirmed, and if it does not, `VKD3D_CONFIG=descriptor_heap`
     would have been silently ignored rather than tried and failed. Checking
     the bundled vkd3d-proton version (`strings` the game's Proton
     installation for a version string, or check Valve's Proton Experimental
     changelog against when #2805 landed upstream) is the next step before
     concluding this workaround doesn't help. A secondary, lower-priority
     workaround for a *different* root cause on older (Turing) hardware
     exists too (`VKD3D_DISABLE_EXTENSIONS=VK_NV_raw_access_chains`, from
     `NVIDIA/open-gpu-kernel-modules#1409`) — likely not relevant to
     Blackwell, and it carries a performance regression.
  4. `open = false` (proprietary kernel modules) as a controlled A/B test —
     now lower priority than (3), since a likely root cause has already
     been identified independent of the kernel module choice; confounds with
     (1) and (3) if done first either way, and `hardware/nvidia.nix`'s own
     comment ("NVIDIA lists this PCI family as requiring its open kernel
     modules") says this will likely just fail to produce a working graphical
     session rather than yield a usable comparison; confirm against current
     NVIDIA documentation before spending time on it, and expect to revert
     immediately either way.
  5. A different driver branch/version (595.45.04 or 590.48.01 above) —
     also now lower priority than (3); none of the available pinned options
     reach 620.70.06 regardless.

  Change exactly one variable at a time and reproduce (or fail to) before
  trying the next, or a fix cannot be attributed. `docs/profiles.md` must be
  corrected to stop recommending GE-Proton for Galactic Racer if this is
  ever actually fixed — right now it correctly says not to.
