# Self-benchmarking

`helix-benchmark` is a lightweight, on-demand CLI for comparing Helix's
performance across machine changes (a Nixpkgs bump, a driver update, a new
generation) rather than a rigorous or exhaustive benchmark suite. Results are
indicative, not scientific: nothing here isolates variables as strictly as a
dedicated review would.

```bash
helix-benchmark            # runs system, compute, llm, then gpu (in that order)
helix-benchmark system     # load average, memory headroom, temperatures, disk free
helix-benchmark profile    # boot time, closure size, PSI and GPU idle-power context
helix-benchmark compute    # sysbench CPU, single-thread and all-thread
helix-benchmark gpu        # vkmark, then Cyberpunk 2077 via Steam + MangoHud if installed
helix-benchmark llm        # Ollama tokens/sec on deepseek-r1:8b
helix-benchmark history    # the last few recorded runs, one line each
```

Every run (except `history`) appends one JSON line to
`~/.local/state/helix/benchmarks/results.jsonl`. That file is mutable user
state, like the rest of `~/.local/state/helix/`; it is never read by any other
Helix module and is safe to delete.

## Automatic Steam game-session captures

The Helix gaming profile configures Steam (not the entire desktop) to
enable MangoHud's Vulkan layer and record samples every 100ms, starting
five seconds after a game initializes. Logging continues until stopped
or the game exits. Timestamped CSVs accumulate privately in
`~/.local/state/helix/game-benchmarks`; the normal MangoHud metadata
header records hardware, kernel and the driver in use at capture time.
Uploads are disabled. No game is launched, killed or monitored by a daemon.

After activating a Helix generation that contains this change, **fully
quit and relaunch Steam once**. Steam processes already running when the
configuration changes retain their previous environment. The NixOS
user-tmpfiles rule creates the logging directory on a fresh user login.
Existing manually set per-game launch options are neither inspected nor
rewritten; a game-specific `MANGOHUD_CONFIG` takes precedence.

```bash
helix-game-benchmarks status
helix-game-benchmarks history --limit 20
helix-game-benchmarks latest
```

The history command reads existing CSVs, never alters them. It prefers
MangoHud's companion `_summary.csv` for the frame-time-derived average
FPS and **1%-low FPS** when available, and clearly labels its fallback
as sampled FPS statistics rather than pretending they are standard
frame-time lows. Games, dates and driver are read from the original
capture; blank driver metadata is reported as `unknown`, never guessed
from whichever driver happens to be running now. Menus, loading, and idle
scenes can dominate a whole-session capture: the figures are only
comparable when graphics settings, resolution, driver and scene are
comparable. No retention purge is configured; remove CSVs intentionally.

Steam's FHS wrapper adds MangoHud's **OpenGL preload shim** alongside
the Vulkan layer. Both 64-bit and 32-bit MangoHud library paths are
available to Steam, including 32-bit Windows OpenGL games running through
Proton, such as Noita. We preload `libMangoHud_shim.so` by absolute store
path (not a bare filename, and not the eager overlay library). This is
limited to Steam; there is no system-wide injection, daemon or mutation
of any game's Steam launch options.

This is set via `extraBwrapArgs = [ "--setenv ..." ]`, directly on the
bubblewrap invocation that creates Steam's sandbox, not via `extraProfile`.
`extraEnv` and `extraProfile` render into the exact same generated FHS
profile script (confirmed in nixpkgs' `pkgs/by-name/st/steam/package.nix`:
both land in one `set -a; <extraEnv>; set +a; <extraProfile>` block), so
an earlier `extraProfile`-based `LD_PRELOAD` export never reached any
game — live process inspection on real hardware showed `MANGOHUD=1`
(set via `extraEnv`) surviving into every process down to the Wine-hosted
game binary itself, while the `extraProfile`-exported `LD_PRELOAD` was
absent from the very first process inside Steam's own sandbox. The
Steam-blessed `mangohud %command%` launch-option pattern works because it
execs as the immediate parent of Steam's per-game launch chain, with no
client-startup step in between to discard it; `extraBwrapArgs` reproduces
that by setting the variable directly on the sandbox's init process,
before any shell-profile script (or Steam's own `steam.sh`) runs at all.

**After activation, fully quit and restart Steam.** A reboot also starts
a fresh client. Keep Noita open for more than the five-second delayed
capture start and confirm a timestamped CSV appears. Then test an ordinary
Vulkan/Proton game, to ensure the preload hasn't regressed the existing
capture path. CI cannot establish end-to-end OpenGL compatibility.

Some native launchers, Steam runtimes, anti-cheat and gamescope wrappers
can filter or override `LD_PRELOAD`. If Steam or a game fails to launch,
use the previously working NixOS generation; don't diagnose a GPU-driver
regression from that symptom alone. Disabling all preloads for an individual
game may remove libraries it needs; do not use `LD_PRELOAD=` as a blanket
workaround.

A session shorter than five seconds may produce no CSV even when injection
is working.

### Managed GPU benchmarking is separate

`helix-benchmark gpu` is an older, explicitly invoked benchmarking mode
that can launch and terminate Cyberpunk 2077. It must not be used for
ordinary passive logging. Its MangoHud-specific launch configuration and
MangoHud/Steam compatibility assumptions remain separate from the
automatic per-session history described above.

## What each category measures

- **system**: a snapshot, not a benchmark — `os.getloadavg()`, `/proc/meminfo`,
  the hottest `/sys/class/thermal` zone, `nvidia-smi` if reachable, and free
  space on `/`. Finishes in under a second; useful context alongside the other
  three.
- **profile**: a read-only production footprint snapshot: exact
  `/run/current-system` closure path, kernel, total boot time from
  `systemd-analyze time`, top eight slow-starting units for diagnosis,
  transitive Nix system-closure size (bytes), CPU/memory/I/O
  pressure-stall 10-second averages, memory availability and a single NVIDIA
  driver/power/utilisation/VRAM sample. Individual unavailable probes return
  `null` or an empty object; they never block a running desktop. Most probes
  have a 12-second timeout and the Nix closure query has a 20-second bound.
  This is **not** an idle certification, cold-boot benchmark, or CPU/GPU
  throughput measurement. It does not contact Infernalnexus, edit settings,
  restart services, or create a Nix derivation.
- **compute**: `sysbench cpu --cpu-max-prime=20000`, once single-threaded and
  once across every reported CPU, each for `--compute-duration` seconds
  (default 10). Reports events/sec; higher is faster. This never touches the
  GPU.
- **gpu**: `vkmark --present-mode immediate` always runs first (a
  deterministic, Vulkan-only synthetic score) as a baseline that needs
  nothing installed beyond the driver. `immediate` is used instead of
  vkmark's own default (`mailbox`, which this GPU/Wayland combination
  rejects outright) or `fifo` (which caps every scene at the display's
  refresh rate, hiding real throughput changes on a fast GPU); the tearing
  it causes does not matter for a few seconds of automated benchmarking. If
  `steam` is installed and Cyberpunk 2077 (Steam app 1091500) is found in
  any registered Steam library, it is then launched via
  `steam steam://rungameid/1091500` after writing a per-executable MangoHud
  config (see the one-time setup above) so FPS logs to a CSV automatically,
  no keypress needed. After `--gpu-load-wait` seconds (default 30, to clear
  loading/menus) plus `--gpu-log-duration` seconds (default 45, the capture
  window), the process is sent `SIGTERM` and the CSV is parsed for
  average/minimum/approximate-1%-low FPS. If Cyberpunk is not installed, or
  no log appears in time, that half is skipped and reported as such — the
  suite never fails because a specific game is absent.
- **llm**: a single `POST /api/generate` to Ollama (`127.0.0.1:11434`) for
  `deepseek-r1:8b` with a fixed prompt, seed and `num_predict` (default 200
  tokens, via `--llm-tokens`). Reports both prompt (prefill) and generation
  (decode) tokens/sec from Ollama's own `prompt_eval_count`/`eval_count` and
  their matching durations — the same figures `ollama run --verbose` would
  show. `deepseek-r1:8b` is the smallest of the declared models
  (`docs/profiles.md`), chosen to keep a single run short.

## Measured optimisation protocol

For changes to the NixOS runtime (driver, kernel, services, memory, desktop
or monitoring), capture an on-Helix baseline on the **same screen resolution,
refresh mode, session type, workspace and background workload**:

```bash
helix-benchmark profile
helix-benchmark system
helix-benchmark compute --compute-duration 15
helix-benchmark llm --llm-tokens 200
helix-benchmark history
```

Repeat after settling temperatures and caches, ideally three times both
before and after. The recorder appends results under
`~/.local/state/helix/benchmarks/results.jsonl`; keep the generation
fingerprint and NVIDIA driver shown in `profile` alongside each result.
Do not average performance numbers across different games/saves/settings or
compare mixed 119.91 Hz/144 Hz display modes. GPU FPS uses the same
controlled in-game scene and capture interval for each run.

For boot performance, compare complete cold-boot timings, not just a
`systemd-analyze blame` line: services can start concurrently, and the
critical chain often differs from the single slowest unit. A profile taken
after a reboot records that boot; a snapshot without a reboot cannot measure
the effect of changed boot policy. For power/memory pressure, settle all
user processes and idle workloads first; a one-sample observation cannot
prove a sustained improvement. If the comparison is noisy or regresses
recoverability, decline the optimisation.

Any claimed speedup should give the baseline and candidate Git revisions,
sample count, medians and variability, workload and environmental conditions,
and an explicit rollback. Do not enable a daemon, disable a health check,
change GPU clocks or reduce recovery retention to win a synthetic score.

## Alpha 8 baseline and closure timing

Run the non-interactive collector on Helix:

```bash
./scripts/helix-assess.sh                 # baseline plus full release gate
./scripts/helix-assess.sh --quick         # baseline plus quick checks
./scripts/helix-assess.sh --profile-only  # no builds or release checks
```

Private results go under
`~/.local/state/helix/assessments/<timestamp>-<revision>/`.
`SUMMARY.txt` records each probe's duration and status; `CLOSURE_TIMINGS.txt`
is written directly by the gate through `HELIX_TIMING_FILE`, so Nix's progress
redraws and control bytes cannot hide the timing markers. The raw gate log is
retained separately for diagnosis. Full validation now times
the system closure separately from the inspected artifacts, and then the
desktop, monitoring, network, and application checks independently.

The `closure-size`, `closure-eval` and `closure-plan` probes distinguish
transitive size, Nix evaluation and a dry-run substitution/build plan.
A `nix-build` duration *includes* evaluating the configuration, downloading
substitutes, and compiling missing dependencies; its elapsed time is not an
isolated compiler benchmark. A repeat build against an unchanged pinned
Nixpkgs can be much faster due to the already-populated store.

The script does not install packages, change drivers, enable global Nix
experimental features, switch system generations, or touch backups. It may
launch the synthetic Vulkan `vkmark` in a graphical session, but deliberately
does not launch or kill a Steam game. `helix-benchmark` writes to its existing
user-local results history; the collector creates private logs.
The current NVIDIA Xid snapshot alone is **not** a controlled driver
qualification. Compare the Xid 109 case file and a repeatable gameplay run
before promoting any different driver.

`tests/system-invariants.nix` now reports the names of failing invariant
modules in one evaluation. Individual source assertions still require
inspection within the reported module.

### Static fixture profiling

The quick/full gate writes `HELIX_TIMING subphase=fixture-*` markers for
each existing static fixture. These are nested within
`subphase=static-fixtures`; do not add the parent and child times together.
The NAS wait fixture formerly imposed a fixed three-second timeout merely
to prove that decimal `08` was accepted. It now uses a one-second deadline
and still asserts that the process remains active until `timeout` exits 124.
This shortens a deliberate test wait without removing the decimal-parsing
regression check or changing the production NAS waiter.

## Ghostty and misleading kernel I/O pressure (2026-11-21)

On Helix kernel 6.18.57, the initial observation was
`procs_blocked=6`, I/O PSI `full avg10=89.90`, and CPU I/O wait
of approximately 37% despite little reported NVMe activity.
The snapshot script counted six threads in `io_cqring_wait`, but it
did **not** filter those threads by owning process despite labelling
the count "Ghostty"; their ownership was not established in that output.

An attempt to switch Ghostty to `epoll` changed the writable config,
but the restart script assumed the executable path ended in
`/bin/ghostty`. The NixOS wrapper defeated that process detector,
and its immediate post-launch readings remained abnormal:
`procs_blocked=6`, `full avg10=91.87`, I/O wait approximately 36%.
That attempt was **not** a verified restart.

When a corrected independent launch test ran later, its **before**
readings were **already** normal: `procs_blocked=0`,
`full avg10=0.39`, and no `io_cqring_wait` threads. Ghostty reported
`async-backend = epoll` as the effective configuration. After launching
with `--gtk-single-instance=false --async-backend=epoll`, the system
still reported `procs_blocked=0`, `full avg10=0.09`, no
`io_cqring_wait` threads, and 0% CPU I/O wait.

These observations are **consistent with** a Ghostty/io_uring
wait-accounting problem and confirm a healthy `epoll` instance,
but **do not constitute a controlled io_uring-versus-epoll A/B**:
the high-to-low transition was not captured with verified Ghostty
process ownership and complete termination. Do not interpret the
initial PSI as evidence of failed storage or assume future pressure
measurements are spurious. The conservative, host-specific workaround
is `async-backend = epoll` in `config/ghostty/config.ghostty`,
deployed to the user's writable baseline by `helix-ghostty-config`
on login. Retain this until a controlled retest or an upstream fix
justifies removing it.

For a future test, record device activity (`iostat -xz 1 5`),
process and thread ownership (`ps -eLo pid,tid,stat,wchan:32,comm`
plus `/proc/<pid>/exe`), I/O PSI and `procs_blocked` for each backend.
Verify the original Ghostty process has exited before launching the
other backend: GTK single-instance invocations can join a still-running
server. Save or detach active terminal work first. Test activation
and runtime measurements remain Helix-only operations.

## Caveats that only a human can resolve

- **No MangoHud log at all usually means the one-time Steam setup above was
  skipped**, not a bug in the capture itself — check that first.
- **Cyberpunk 2077's FPS number depends on where the save left off.** There is
  no official in-game benchmark mode; this tool assumes the last save (or
  whatever `steam://rungameid/` resumes into) drops into a representative,
  GPU-bound scene — ideally driving or combat in Night City, not a loading
  screen or a menu. A save that opens into a static menu will produce a
  meaningless (or absent) FPS log. Keep a save purpose-built for this.
- **The MangoHud CSV schema is not Nix-verified.** The FPS column is detected
  by name match (`"fps" in column.lower()`) rather than a pinned schema,
  because the build cannot launch a Vulkan application to check it. If
  MangoHud changes its CSV header, `gpu` will report the log file path without
  parsed numbers instead of crashing — inspect the CSV by hand in that case.
- **`vkmark`'s score and Cyberpunk's FPS are not comparable to each other**,
  only to themselves across runs on this machine.
- A build and `check.sh --full` only prove `helix-benchmark`'s subcommands
  exist and its runtime closure has the tools it calls; they cannot launch
  Steam, Ollama, or a Vulkan context, so none of the actual numbers above are
  evaluation-verified. Run it for real after a change you want to measure.
