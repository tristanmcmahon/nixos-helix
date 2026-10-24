#!/usr/bin/env python3
"""Lightweight self-benchmarking: system, raw compute, GPU and local LLM."""

from __future__ import annotations

import argparse
import csv
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any

STATE_DIR = pathlib.Path.home() / ".local/state/helix/benchmarks"
RESULTS_FILE = STATE_DIR / "results.jsonl"
MANGOHUD_LOG_DIR = STATE_DIR / "mangohud-logs"

OLLAMA_URL = "http://127.0.0.1:11434"
OLLAMA_MODEL = "deepseek-r1:8b"
OLLAMA_PROMPT = "Explain the significance of the number 42 in one paragraph."

CYBERPUNK_APPID = "1091500"
CYBERPUNK_PROCESS_PATTERN = "Cyberpunk2077.exe"


class BenchmarkSkipped(RuntimeError):
    """A benchmark category could not run; not a failure of the suite."""


@dataclass
class Result:
    category: str
    metrics: dict[str, Any] = field(default_factory=dict)
    skipped: str | None = None


def run_system() -> Result:
    load1, load5, load15 = os.getloadavg()
    mem_total = mem_available = None
    for line in pathlib.Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
        if line.startswith("MemTotal:"):
            mem_total = int(line.split()[1])
        elif line.startswith("MemAvailable:"):
            mem_available = int(line.split()[1])

    cpu_temp_c = None
    thermal_zones = sorted(pathlib.Path("/sys/class/thermal").glob("thermal_zone*/temp"))
    readings = []
    for zone in thermal_zones:
        try:
            readings.append(int(zone.read_text().strip()) / 1000)
        except (OSError, ValueError):
            continue
    if readings:
        cpu_temp_c = max(readings)

    disk_usage = shutil.disk_usage("/")

    gpu: dict[str, Any] = {}
    try:
        output = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        ).stdout.strip()
        temp, util, mem_used, mem_total_mib = (part.strip() for part in output.split(","))
        gpu = {
            "temperature_c": float(temp),
            "utilization_percent": float(util),
            "memory_used_mib": float(mem_used),
            "memory_total_mib": float(mem_total_mib),
        }
    except (OSError, subprocess.SubprocessError, ValueError):
        pass

    return Result(
        "system",
        {
            "load_average": {"1m": load1, "5m": load5, "15m": load15},
            "memory_available_percent": (
                round(100 * mem_available / mem_total, 1)
                if mem_total and mem_available
                else None
            ),
            "cpu_temperature_c": cpu_temp_c,
            "disk_free_percent_root": round(100 * disk_usage.free / disk_usage.total, 1),
            "gpu": gpu,
        },
    )


def _sysbench_events_per_second(threads: int, max_prime: int, duration: int) -> float:
    output = subprocess.run(
        [
            "sysbench",
            "cpu",
            f"--cpu-max-prime={max_prime}",
            f"--threads={threads}",
            f"--time={duration}",
            "run",
        ],
        capture_output=True,
        text=True,
        timeout=duration + 30,
        check=True,
    ).stdout
    match = re.search(r"events per second:\s*([\d.]+)", output)
    if not match:
        raise BenchmarkSkipped("sysbench did not report an events-per-second figure")
    return float(match.group(1))


def run_compute(duration: int) -> Result:
    threads = os.cpu_count() or 1
    single = _sysbench_events_per_second(1, 20000, duration)
    multi = _sysbench_events_per_second(threads, 20000, duration)
    return Result(
        "compute",
        {
            "sysbench_single_thread_events_per_sec": single,
            "sysbench_all_threads_events_per_sec": multi,
            "threads": threads,
        },
    )


def _run_vkmark() -> dict[str, Any]:
    try:
        # mailbox (vkmark's default) is not supported by every Vulkan/Wayland
        # combination; fifo always is, but caps FPS at the display refresh
        # rate, making it useless for spotting real GPU throughput changes.
        # immediate is uncapped (and tears, which does not matter for a few
        # seconds of automated benchmarking) and is the most discriminative.
        completed = subprocess.run(
            ["vkmark", "--present-mode", "immediate"],
            capture_output=True,
            text=True,
            timeout=300,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return {"error": f"could not run vkmark: {error}"}
    output = completed.stdout
    match = re.search(r"[Ss]core[:\s]+(\d+)", output)
    if match:
        return {"score": float(match.group(1))}
    tail = "\n".join((output + completed.stderr).strip().splitlines()[-5:])
    return {"error": f"vkmark produced no parseable score; last output:\n{tail}"}


def _steam_library_paths() -> list[pathlib.Path]:
    candidates = [
        pathlib.Path.home() / ".local/share/Steam/steamapps/libraryfolders.vdf",
        pathlib.Path.home() / ".steam/steam/steamapps/libraryfolders.vdf",
    ]
    paths = []
    for candidate in candidates:
        if not candidate.is_file():
            continue
        text = candidate.read_text(encoding="utf-8", errors="ignore")
        for match in re.finditer(r'"path"\s+"([^"]+)"', text):
            paths.append(pathlib.Path(match.group(1)))
    return paths


def _find_cyberpunk_install() -> pathlib.Path | None:
    for library in _steam_library_paths():
        manifest = library / "steamapps" / f"appmanifest_{CYBERPUNK_APPID}.acf"
        if manifest.is_file():
            return library
    return None


def _write_mangohud_config(log_duration: int) -> None:
    # Steam normally already has a client running; `steam steam://rungameid/`
    # just messages that existing client over IPC, so environment variables
    # set on our short-lived `steam` invocation never reach the game process
    # it actually launches (confirmed: the running client's own environment
    # has no MANGOHUD set, regardless of what we pass here). MangoHud's
    # per-executable config file is read by the layer itself, independent of
    # how it was enabled, so it works whether MangoHud was turned on via
    # Steam's own "Enable Mangohud" Properties toggle or a launch option of
    # `mangohud %command%` — either is still required once, by hand; Helix
    # must not edit Steam's own launch-options VDF to force it.
    config_dir = pathlib.Path.home() / ".config/MangoHud"
    config_dir.mkdir(parents=True, exist_ok=True)
    config_file = config_dir / f"{CYBERPUNK_PROCESS_PATTERN}.conf"
    config_file.write_text(
        f"autostart_log=1\nlog_duration={log_duration}\noutput_folder={MANGOHUD_LOG_DIR}\n",
        encoding="utf-8",
    )


def _run_cyberpunk(load_wait: int, log_duration: int) -> dict[str, Any]:
    if shutil.which("steam") is None:
        raise BenchmarkSkipped("Steam is not installed (enable helix.gaming)")
    if _find_cyberpunk_install() is None:
        raise BenchmarkSkipped("Cyberpunk 2077 was not found in any Steam library")

    MANGOHUD_LOG_DIR.mkdir(parents=True, exist_ok=True)
    before = set(MANGOHUD_LOG_DIR.glob("*.csv"))
    _write_mangohud_config(log_duration)

    subprocess.Popen(
        ["steam", f"steam://rungameid/{CYBERPUNK_APPID}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    print(
        f"  Launched Cyberpunk 2077 via Steam; waiting {load_wait}s to load, "
        f"then logging for {log_duration}s...",
        file=sys.stderr,
    )
    try:
        time.sleep(load_wait + log_duration + 5)
    except KeyboardInterrupt:
        subprocess.run(["pkill", "-TERM", "-f", CYBERPUNK_PROCESS_PATTERN], check=False)
        raise

    subprocess.run(["pkill", "-TERM", "-f", CYBERPUNK_PROCESS_PATTERN], check=False)

    after = set(MANGOHUD_LOG_DIR.glob("*.csv"))
    new_logs = after - before
    if not new_logs:
        raise BenchmarkSkipped(
            "no MangoHud log appeared; either MangoHud is not enabled for "
            "Cyberpunk 2077 in Steam (Properties -> enable it, or set launch "
            "options to 'mangohud %command%', once) or it loaded into a menu "
            "rather than gameplay"
        )
    log_file = max(new_logs, key=lambda path: path.stat().st_mtime)

    with log_file.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    fps_key = next((key for key in (rows[0].keys() if rows else []) if "fps" in key.lower()), None)
    if not rows or fps_key is None:
        return {"log_file": str(log_file)}
    samples = [float(row[fps_key]) for row in rows if row.get(fps_key)]
    if not samples:
        return {"log_file": str(log_file)}
    samples.sort()
    return {
        "avg_fps": round(sum(samples) / len(samples), 1),
        "min_fps": round(samples[0], 1),
        "p1_low_fps": round(samples[max(0, len(samples) // 100 - 1)], 1),
        "samples": len(samples),
        "log_file": str(log_file),
    }


def run_gpu(load_wait: int, log_duration: int) -> Result:
    metrics: dict[str, Any] = {"vkmark": _run_vkmark()}
    try:
        metrics["cyberpunk_2077"] = _run_cyberpunk(load_wait, log_duration)
    except BenchmarkSkipped as error:
        metrics["cyberpunk_2077"] = {"skipped": str(error)}
    return Result("gpu", metrics)


def run_llm(num_predict: int) -> Result:
    body = {
        "model": OLLAMA_MODEL,
        "prompt": OLLAMA_PROMPT,
        "stream": False,
        "options": {"seed": 42, "num_predict": num_predict},
    }
    request = urllib.request.Request(
        f"{OLLAMA_URL}/api/generate",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            payload = json.loads(response.read())
    except urllib.error.URLError as error:
        raise BenchmarkSkipped(
            f"Ollama is not reachable at {OLLAMA_URL} (enable helix.localLlm): {error}"
        ) from error
    except urllib.error.HTTPError as error:
        raise BenchmarkSkipped(f"Ollama rejected the request: {error.read().decode(errors='replace')}") from error

    eval_count = payload.get("eval_count")
    eval_duration = payload.get("eval_duration")
    prompt_eval_count = payload.get("prompt_eval_count")
    prompt_eval_duration = payload.get("prompt_eval_duration")
    metrics = {
        "model": OLLAMA_MODEL,
        "generated_tokens_per_sec": (
            round(eval_count / (eval_duration / 1e9), 1)
            if eval_count and eval_duration
            else None
        ),
        "prompt_tokens_per_sec": (
            round(prompt_eval_count / (prompt_eval_duration / 1e9), 1)
            if prompt_eval_count and prompt_eval_duration
            else None
        ),
    }
    return Result("llm", metrics)


def _print_result(result: Result) -> None:
    print(f"\n== {result.category} ==")
    if result.skipped:
        print(f"  skipped: {result.skipped}")
        return
    print(json.dumps(result.metrics, indent=2))


def _record(results: list[Result]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    record = {"timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
    for result in results:
        record[result.category] = (
            {"skipped": result.skipped} if result.skipped else result.metrics
        )
    with RESULTS_FILE.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record) + "\n")


def run_history(count: int) -> int:
    if not RESULTS_FILE.is_file():
        print("No benchmark results recorded yet.")
        return 0
    lines = RESULTS_FILE.read_text(encoding="utf-8").splitlines()[-count:]
    for line in lines:
        record = json.loads(line)
        compute = record.get("compute", {})
        gpu = record.get("gpu", {})
        llm = record.get("llm", {})
        cyberpunk = gpu.get("cyberpunk_2077", {}) if isinstance(gpu, dict) else {}
        vkmark = gpu.get("vkmark", {}) if isinstance(gpu, dict) else {}
        print(
            f"{record['timestamp']}  "
            f"compute={compute.get('sysbench_all_threads_events_per_sec', '-')}  "
            f"vkmark={vkmark.get('score', vkmark.get('error', '-'))}  "
            f"cyberpunk_fps={cyberpunk.get('avg_fps', '-')}  "
            f"llm_tok/s={llm.get('generated_tokens_per_sec', '-')}"
        )
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("system", "compute", "gpu", "llm", "all", "history"),
        nargs="?",
        default="all",
    )
    parser.add_argument(
        "--compute-duration",
        type=int,
        default=10,
        help="seconds per sysbench CPU run (default: 10)",
    )
    parser.add_argument(
        "--gpu-load-wait",
        type=int,
        default=30,
        help="seconds to let Cyberpunk 2077 load before logging FPS (default: 30)",
    )
    parser.add_argument(
        "--gpu-log-duration",
        type=int,
        default=45,
        help="seconds of MangoHud FPS logging to capture (default: 45)",
    )
    parser.add_argument(
        "--llm-tokens",
        type=int,
        default=200,
        help="tokens to generate for the LLM benchmark (default: 200)",
    )
    parser.add_argument(
        "--history-count",
        type=int,
        default=10,
        help="number of past runs to show with the history command (default: 10)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "history":
        return run_history(args.history_count)

    categories = {
        "system": lambda: run_system(),
        "compute": lambda: run_compute(args.compute_duration),
        "gpu": lambda: run_gpu(args.gpu_load_wait, args.gpu_log_duration),
        "llm": lambda: run_llm(args.llm_tokens),
    }
    selected = list(categories) if args.command == "all" else [args.command]

    results = []
    try:
        for name in selected:
            try:
                result = categories[name]()
            except BenchmarkSkipped as error:
                result = Result(name, skipped=str(error))
            except subprocess.SubprocessError as error:
                result = Result(name, skipped=f"benchmark command failed: {error}")
            results.append(result)
            _print_result(result)
    except KeyboardInterrupt:
        print("\nInterrupted; recording what finished so far.", file=sys.stderr)
        if results:
            _record(results)
        return 130

    _record(results)
    print(f"\nRecorded to {RESULTS_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
