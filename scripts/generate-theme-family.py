#!/usr/bin/env python3
"""Render the Helix theme family from config/theme/palettes.nix.

Templates mark every themed value explicitly as @role@ (upper-case hex),
@role:lower@, @role:bare@ (lower-case hex without #), @role:rgb@ ("r,g,b") or
@role:rgb_spaced@ ("r, g, b"), plus @scheme@ and @name@. Unlike substituting
Fern's hex values, a colour that merely equals a Fern value is never rewritten.
"""

from __future__ import annotations

import json
import pathlib
import re
import shutil
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: generate-theme-family.py PALETTES_JSON THEME_SOURCE OUTPUT")

PALETTES = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
SOURCE = pathlib.Path(sys.argv[2])
OUTPUT = pathlib.Path(sys.argv[3])
TEMPLATES = SOURCE / "templates"
PLACEHOLDER = re.compile(r"@([A-Za-z]+)(?::([a-z_]+))?@")


def rgb(value: str) -> list[str]:
    return [str(int(value[index : index + 2], 16)) for index in (1, 3, 5)]


def render(text: str, theme: dict[str, str], scheme: str) -> str:
    def substitute(match: re.Match[str]) -> str:
        role, form = match.group(1), match.group(2)
        if role == "scheme" and form is None:
            return scheme
        if role == "name" and form is None:
            return theme["name"]
        value = theme[role]
        forms = {
            None: value,
            "lower": value.lower(),
            "bare": value[1:].lower(),
            "rgb": ",".join(rgb(value)),
            "rgb_spaced": ", ".join(rgb(value)),
        }
        return forms[form]

    rendered = PLACEHOLDER.sub(substitute, text)
    if PLACEHOLDER.search(rendered):
        raise SystemExit(f"unrendered placeholder in output for {scheme}")
    return rendered


for key in PALETTES["order"]:
    theme = PALETTES["themes"][key]
    scheme = "HelixGraphite" + theme["name"].replace(" ", "")
    destination = OUTPUT / key
    destination.mkdir(parents=True, exist_ok=True)
    for template in sorted(TEMPLATES.iterdir()):
        name = template.name.replace("HelixGraphite.", f"{scheme}.")
        text = template.read_text(encoding="utf-8")
        (destination / name).write_text(render(text, theme, scheme), encoding="utf-8")

# GTK stays maintained Breeze-Dark for every member of the family.
for filename in ("gtk-3.0-settings.ini", "gtk-4.0-settings.ini"):
    shutil.copy2(SOURCE / filename, OUTPUT / filename)
