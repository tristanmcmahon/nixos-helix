#!/usr/bin/env python3
"""Offline regressions: real MangoHud CSV shape, summaries and missing metadata."""
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "game_history", ROOT / "scripts/helix-game-benchmarks.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary)
    game = folder / "Warhammer 40000 Space Marine 2 - Retail_2026-11-22_13-38-10.csv"
    game.write_text(
        "os,cpu,gpu,ram,kernel,driver,cpuscheduler\n"
        "NixOS,AMD CPU,RTX 5080,32GiB,6.18.57,,performance\n"
        "fps,frametime,gpu_load,elapsed\n"
        "60,16.7,90,100\n"
        "120,8.3,99,200\n"
        "0,0,0,300\n"
        "NaN,0,0,400\n",
        encoding="utf-8",
    )
    summary = game.with_name(game.stem + "_summary.csv")
    summary.write_text(
        "0.1% Min FPS,1% Min FPS,97% Percentile FPS,Average FPS,GPU Load\n"
        "24,45,115,95,92\n",
        encoding="utf-8",
    )

    record = module.read_capture(game)
    assert record is not None
    assert record["game"] == "Warhammer 40000 Space Marine 2 - Retail"
    assert record["date"] == "2026-11-22 13:38"
    assert record["driver"] == "unknown"  # Never backfill from a later driver!
    assert record["gpu"] == "RTX 5080"
    assert record["samples"] == 2
    assert record["average_fps"] == 95.0
    assert record["low_fps"] == 45.0
    assert record["source"] == "summary"

    summary.unlink()
    sampled = module.read_capture(game)
    assert sampled is not None
    assert sampled["source"] == "samples"
    assert sampled["average_fps"] == 90.0
    assert sampled["low_fps"] == 60.0

    summary.write_text(
        "1% Min FPS,Average FPS\nNaN,-1\n", encoding="utf-8"
    )
    assert module.read_capture(game)["source"] == "samples"
    assert module.positive_number("inf") is None
    assert module.positive_number("") is None
    assert module.positive_number("12.5") == 12.5
    assert len(module.captures(folder, 10)) == 1

    bad = folder / "not-a-capture.csv"
    bad.write_text("hello,world\n1,2\n", encoding="utf-8")
    assert module.read_capture(bad) is None
    assert len(module.captures(folder, 10)) == 1

print("Passive MangoHud CSV and summary parsing: PASS")
