#!/usr/bin/env python3
"""Validate repository-relative Markdown links without network access."""

import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
failures = []
for document in [root / "README.md", *sorted((root / "docs").glob("*.md"))]:
    text = document.read_text(encoding="utf-8")
    for target in re.findall(r"\[[^]]*\]\(([^)]+)\)", text):
        if target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        relative = target.split("#", 1)[0]
        if relative and not (document.parent / relative).resolve().exists():
            failures.append(f"{document.relative_to(root)}: missing {target}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
