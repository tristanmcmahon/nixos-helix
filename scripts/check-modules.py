#!/usr/bin/env python3
"""Check that maintained Nix modules are reachable exactly once."""

from __future__ import annotations

import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
entry = root / "configuration.nix"
dormant_roots: set[pathlib.Path] = set()
module_dirs = ("hardware", "desktop", "system", "services", "profiles", "packages", "shell")
maintained = {
    path.resolve()
    for directory in module_dirs
    for path in (root / directory).glob("*.nix")
}


def imports(path: pathlib.Path) -> list[pathlib.Path]:
    text = path.read_text(encoding="utf-8")
    return [
        (path.parent / match).resolve()
        for match in re.findall(r"(?<![A-Za-z0-9_])((?:\.\.?/)[A-Za-z0-9_./+-]+\.nix)", text)
    ]


reachable: set[pathlib.Path] = set()
edges: list[tuple[pathlib.Path, pathlib.Path]] = []
pending = [entry.resolve(), *sorted(dormant_roots)]
while pending:
    parent = pending.pop()
    if parent in reachable:
        continue
    reachable.add(parent)
    for child in imports(parent):
        if child == parent:
            continue
        if child in maintained or child == (root / "hardware-configuration.nix").resolve():
            edges.append((parent, child))
            pending.append(child)

failures: list[str] = []
for module in sorted(maintained - reachable):
    failures.append(f"unreachable maintained module: {module.relative_to(root)}")

active_edges: dict[pathlib.Path, list[pathlib.Path]] = {}
for parent, child in edges:
    active_edges.setdefault(child, []).append(parent)
for child, parents in sorted(active_edges.items()):
    if len(parents) > 1:
        locations = ", ".join(str(parent.relative_to(root)) for parent in parents)
        failures.append(f"duplicate module import: {child.relative_to(root)} via {locations}")

font_owners = []
for module in maintained:
    text = module.read_text(encoding="utf-8")
    if "fonts.packages" in text or "fontconfig.defaultFonts" in text:
        font_owners.append(module.relative_to(root))
if sorted(font_owners) != [pathlib.Path("desktop/fonts.nix")]:
    failures.append(f"font policy owners: {', '.join(map(str, sorted(font_owners)))}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)

print("Maintained module reachability, imports, and font ownership passed.")
