# Self-benchmarking

`helix-benchmark` is a lightweight, on-demand CLI for comparing Helix's
performance across machine changes (a Nixpkgs bump, a driver update, a new
generation) rather than a rigorous or exhaustive benchmark suite. Results are
indicative, not scientific: nothing here isolates variables as strictly as a
dedicated review would.

```bash
helix-benchmark            # runs system, compute, llm, then gpu (in that order)
helix-benchmark system     # load average, memory headroom, temperatures, disk free
helix-benchmark compute    # sysbench CPU, single-thread and all-thread
helix-benchmark gpu        # vkmark, then Cyberpunk 2077 via Steam + MangoHud if installed
helix-benchmark llm        # Ollama tokens/sec on deepseek-r1:8b
helix-benchmark history    # the last few recorded runs, one line each
```

Every run (except `history`) appends one JSON line to
`~/.local/state/helix/benchmarks/results.jsonl`. That file is mutable user
state, like the rest of `~/.local/state/helix/`; it is never read by any other
Helix module and is safe to delete.

## One-time setup for the Cyberpunk 2077 FPS capture

Enable MangoHud for Cyberpunk 2077 once, by hand, in Steam: right-click it ->
Properties, and either tick its "Enable Mangohud" option, or set Launch
Options to `mangohud %command%`. This is a deliberate manual step, not
something `helix-benchmark` does for you: Steam's client is normally already
running, so a fresh `steam steam://rungameid/...` call only messages that
existing client over IPC — environment variables set on that call never reach
the game process it actually launches. Helix also must not edit Steam's own
launch-options VDF to force this; that file is Steam's mutable state, not
Helix's to own.

Once MangoHud is enabled for the game by either of those means,
`helix-benchmark gpu` writes `~/.config/MangoHud/Cyberpunk2077.exe.conf` with
the current `--gpu-log-duration` before every launch, which MangoHud reads by
executable name regardless of how its layer was turned on. No further setup
is needed after that.

## What each category measures

- **system**: a snapshot, not a benchmark — `os.getloadavg()`, `/proc/meminfo`,
  the hottest `/sys/class/thermal` zone, `nvidia-smi` if reachable, and free
  space on `/`. Finishes in under a second; useful context alongside the other
  three.
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
