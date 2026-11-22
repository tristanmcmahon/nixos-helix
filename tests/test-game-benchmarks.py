#!/usr/bin/env python3
"""Offline regression tests for the passive MangoHud history reader."""
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
    game = folder / "SpaceMarine2_2026-11-22_12-00-00.csv"
    game.write_text(
        "os,cpu,gpu,ram,kernel,driver,cpuscheduler\n"
        "NixOS,AMD CPU,RTX 5080,32GiB,6.18.57,620.70.06,performance\n"
        "fps,frametime,gpu_load,elapsed\n"
        "60,16.7,90,100\n"
        "120,8.3,99,200\n"
        "0,0,0,300\n"
        "NaN,0,0,400\n",
        encoding="utf-8",
    )
    (folder / "SpaceMarine2_2026-11-22_12-00-00_summary.csv").write_text(
        "summary,not-a-capture\n", encoding="utf-8"
    )

    record = module.read_capture(game)
    assert record is not None
    assert record["game"] == "SpaceMarine2"
    assert record["driver"] == "620.70.06"
    assert record["gpu"] == "RTX 5080"
    assert record["samples"] == 2
    assert record["average_fps"] == 90.0
    assert record["low_sample_fps"] == 60.0

    assert len(module.captures(folder, 10)) == 1
    bad = folder / "not-a-capture.csv"
    bad.write_text("hello,world\n1,2\n", encoding="utf-8")
    assert module.read_capture(bad) is None
    assert len(module.captures(folder, 10)) == 1

print("Passive MangoHud capture parsing: PASS")
