#!/usr/bin/env python3
"""Read passive MangoHud game captures; never launch or modify a game."""

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
DATE_SUFFIX = re.compile(
    r"[-_](\d{4})[-_](\d{2})[-_](\d{2})[-_](\d{2})[-_](\d{2})[-_](\d{2})$"
)


def positive_number(value: str | None) -> float | None:
    try:
        number = float(value)
    except (ValueError, TypeError):
        return None
    return number if math.isfinite(number) and number > 0 else None


def read_summary(path: Path) -> tuple[float, float] | None:
    """Prefer the FPS figures MangoHud itself writes into companion summaries."""
    summary_path = path.with_name(path.stem + "_summary.csv")
    try:
        with summary_path.open(newline="", encoding="utf-8", errors="replace") as handle:
            rows = csv.DictReader(handle)
            row = next(rows, None)
            if not row:
                return None
            fields = {name.strip().casefold(): value for name, value in row.items() if name}
            average = positive_number(fields.get("average fps"))
            low = positive_number(fields.get("1% min fps"))
            if average is not None and low is not None:
                return (average, low)
    except (OSError, csv.Error):
        return None
    return None


def capture_label(path: Path) -> tuple[str, str]:
    """Extract the game and launch timestamp from MangoHud's filename."""
    match = DATE_SUFFIX.search(path.stem)
    if match:
        try:
            timestamp = datetime(*(int(v) for v in match.groups()))
            return (path.stem[:match.start()], timestamp.strftime("%Y-%m-%d %H:%M"))
        except ValueError:
            pass
    return (path.stem, datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d %H:%M"))


def read_capture(path: Path) -> dict | None:
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
        game, timestamp = capture_label(path)
    except (OSError, csv.Error):
        return None

    if not fps:
        return None

    # MangoHud summary metrics are based on frametime data and are the
    # authoritative average and 1%-low if present. Sampled FPS statistics
    # are deliberately labelled differently: they are not true 1%-lows.
    summary = read_summary(path)
    if summary is not None:
        avg, low = summary
        source = "summary"
    else:
        count = max(1, math.ceil(len(fps) / 100))
        avg = statistics.fmean(fps)
        low = statistics.fmean(sorted(fps)[:count])
        source = "samples"

    return {
        "game": game or path.stem,
        "date": timestamp,
        "driver": metadata.get("driver", "").strip() or "unknown",
        "gpu": metadata.get("gpu", "").strip() or "unknown",
        "samples": len(fps),
        "average_fps": avg,
        "low_fps": low,
        "source": source,
        "file": path,
    }


def captures(directory: Path, limit: int) -> list[dict]:
    if not directory.is_dir():
        return []
    try:
        candidates = sorted(
            (p for p in directory.glob("*.csv") if not p.stem.endswith("_summary")),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
    except OSError:
        return []
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
    parser.add_argument("command", nargs="?", default="history",
                        choices=("history", "latest", "status"))
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
        print("Requires a fresh Steam process after the Helix gaming update.")
        return 0

    rows = captures(args.directory, 1 if args.command == "latest" else args.limit)
    if not rows:
        print(f"No complete MangoHud FPS captures in {args.directory}")
        return 0
    for record in rows:
        if record["source"] == "summary":
            stats = (
                f"avg={record['average_fps']:.1f}fps  "
                f"1%-low={record['low_fps']:.1f}fps"
            )
        else:
            stats = (
                f"sample-mean={record['average_fps']:.1f}fps  "
                f"lowest-1%-samples={record['low_fps']:.1f}fps"
            )
        print(
            f"{record['date']}  {record['game']}  {stats}  "
            f"n={record['samples']}  driver={record['driver']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
