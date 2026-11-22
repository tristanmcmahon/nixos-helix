#!/usr/bin/env python3
"""List passive MangoHud game-session captures, without touching Steam."""

from __future__ import annotations

import argparse
import csv
from datetime import datetime
import math
from pathlib import Path
import re
import statistics

DEFAULT_DIRECTORY = Path.home() / ".local/state/helix/game-benchmarks"
METADATA = ("os", "cpu", "gpu", "ram", "kernel", "driver", "cpuscheduler")


def read_capture(path: Path) -> dict | None:
    """Parse a MangoHud CSV system header and its sampled FPS records."""
    metadata: dict[str, str] = {}
    metrics: list[str] | None = None
    fps: list[float] = []
    try:
        with path.open(newline="", encoding="utf-8", errors="replace") as handle:
            rows = csv.reader(handle)
            for row in rows:
                headings = [field.strip().lower() for field in row]
                if tuple(headings[:7]) == METADATA:
                    try:
                        metadata = dict(zip(METADATA, next(rows)))
                    except StopIteration:
                        return None
                    continue
                if "fps" in headings and "frametime" in headings:
                    metrics = headings
                    continue
                if metrics is None or not row:
                    continue
                try:
                    value = float(row[metrics.index("fps")])
                except (IndexError, ValueError):
                    continue
                if math.isfinite(value) and value > 0:
                    fps.append(value)
        finished = path.stat().st_mtime
    except (OSError, csv.Error):
        return None

    if not fps:
        return None

    # A simple average of the slowest 1% of equally spaced FPS samples;
    # not a frame-weighted or controlled-sequence 1%-low benchmark.
    low_count = max(1, math.ceil(len(fps) / 100))
    low = sorted(fps)[:low_count]
    game = re.sub(r"[-_]\d{4}[-_]\d{2}[-_]\d{2}.*$", "", path.stem)
    return {
        "game": game or path.stem,
        "date": datetime.fromtimestamp(finished).strftime("%Y-%m-%d %H:%M"),
        "driver": metadata.get("driver", "unknown"),
        "gpu": metadata.get("gpu", "unknown"),
        "samples": len(fps),
        "average_fps": statistics.fmean(fps),
        "low_sample_fps": statistics.fmean(low),
        "file": path,
    }


def captures(directory: Path, limit: int) -> list[dict]:
    if not directory.is_dir():
        return []
    candidates = sorted(
        (p for p in directory.glob("*.csv") if not p.stem.endswith("_summary")),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    found = []
    for path in candidates:
        record = read_capture(path)
        if record is not None:
            found.append(record)
        if len(found) >= limit:
            break
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command", nargs="?", default="history",
        choices=("history", "latest", "status"),
    )
    parser.add_argument("--limit", type=int, default=10,
                        help="max sessions to show (default: 10)")
    parser.add_argument("--directory", type=Path, default=DEFAULT_DIRECTORY,
                        help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.limit < 1:
        parser.error("--limit must be at least 1")

    if args.command == "status":
        count = len(list(args.directory.glob("*.csv"))) if args.directory.is_dir() else 0
        print(f"Capture directory: {args.directory}")
        print(f"CSV files: {count}")
        print("Steam must be restarted after the Helix gaming update.")
        return 0

    rows = captures(args.directory, 1 if args.command == "latest" else args.limit)
    if not rows:
        print(f"No complete MangoHud FPS captures in {args.directory}")
        return 0
    for record in rows:
        print(
            f"{record['date']}  {record['game']}  "
            f"avg={record['average_fps']:.1f}fps  "
            f"lowest-1%-samples={record['low_sample_fps']:.1f}fps  "
            f"n={record['samples']}  driver={record['driver']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
