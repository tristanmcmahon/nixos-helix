#!/usr/bin/env python3
"""Controlled A/B benchmark of existing and single-process Helix Nix checks.

No writes to NixOS state, no build, no network requests by the Python process.
Nix evaluation may fetch the pinned release through normal Nixpkgs resolution.
"""

import argparse
import json
import pathlib
import re
import shutil
import statistics
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASELINE = [
    "tests/system-invariants.nix",
    "tests/monitoring-disabled.nix",
    "tests/emulation-disabled.nix",
    "tests/features-disabled.nix",
]
BATCHED = ["tests/quick-evaluations.nix"]


def measure(paths):
    started = time.perf_counter()
    peak_kib = None
    time_bin = shutil.which("time")
    for path in paths:
        command = ["nix-instantiate", "--eval", "--strict", path]
        if time_bin:
            command = [time_bin, "-f", "HELIX_PEAK_KIB=%M", *command]
        completed = subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=True,
        )
        if completed.stdout.strip() != "true":
            raise RuntimeError(f"{path} did not return true: {completed.stdout!r}")
        usage = re.search(r"HELIX_PEAK_KIB=(\\d+)", completed.stderr)
        if usage:
            peak_kib = max(peak_kib or 0, int(usage.group(1)))
    return round(time.perf_counter() - started, 4), peak_kib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.samples <= 10:
        parser.error("--samples must be 1..10")

    # First touches are not comparable: initialise both paths before sampling.
    print("Warming baseline and batched evaluation...", flush=True)
    measure(BASELINE)
    measure(BATCHED)
    observations = {"baseline": [], "batched": []}
    peak_memory = {"baseline": [], "batched": []}
    for i in range(args.samples):
        # Alternate ordering to reduce system cache and temperature bias.
        for method in (("baseline", "batched") if i % 2 == 0 else ("batched", "baseline")):
            paths = BASELINE if method == "baseline" else BATCHED
            seconds, memory_kib = measure(paths)
            observations[method].append(seconds)
            peak_memory[method].append(memory_kib)
            print(
                f"sample={i + 1} method={method} seconds={seconds:.4f}"
                f" peak_nix_process_kib={memory_kib}",
                flush=True,
            )

    before = statistics.median(observations["baseline"])
    after = statistics.median(observations["batched"])
    summary = {
        "kind": "helix-quick-invariants-ab-v1",
        "samples_per_method": args.samples,
        "baseline_four_process_seconds": round(before, 4),
        "batched_one_process_seconds": round(after, 4),
        "relative_change_percent": round(100 * (after - before) / before, 2),
        "baseline_samples_seconds": observations["baseline"],
        "batched_samples_seconds": observations["batched"],
        "baseline_peak_nix_process_samples_kib": peak_memory["baseline"],
        "batched_peak_nix_process_samples_kib": peak_memory["batched"],
    }
    print("RESULT " + json.dumps(summary, sort_keys=True), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
