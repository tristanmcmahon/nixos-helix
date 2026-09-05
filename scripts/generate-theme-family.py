#!/usr/bin/env python3
"""Generate Helix theme siblings by translating the canonical Fern assets."""

from __future__ import annotations

import pathlib
import shutil
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: generate-theme-family.py THEME_SOURCE GHOSTTY_PROFILE OUTPUT")

SOURCE = pathlib.Path(sys.argv[1])
GHOSTTY_PROFILE = pathlib.Path(sys.argv[2])
OUTPUT = pathlib.Path(sys.argv[3])

PALETTES = {
    "fern": ("Fern", "#67B87A", "#81C995", "#3E7650", "#315E3E", "#181C19", "#232824", "#303832", "#3A443C"),
    "petrol": ("Petrol", "#5FA8A3", "#79C2BC", "#386D69", "#2D5754", "#171D1C", "#222B29", "#2E3937", "#394846"),
    "plum": ("Plum", "#A47AB8", "#C096D0", "#654A73", "#50395B", "#1C181E", "#29232C", "#37303A", "#473C4B"),
    "oxide": ("Oxide", "#BE7A55", "#D69772", "#794C35", "#603B2B", "#1D1917", "#2B2521", "#39312C", "#4A4039"),
    "amber": ("Amber", "#C3A35D", "#D8BC7A", "#786537", "#5D4E2C", "#1D1B16", "#2A2720", "#38342A", "#494435"),
    "rosewood": ("Rosewood", "#B66E7D", "#CF8997", "#734550", "#59363E", "#1D1719", "#2B2225", "#392D31", "#493A3F"),
    "hotdog": ("Hot Dog Stand", "#FF0000", "#FFFFFF", "#C00000", "#FF0000", "#FFFF00", "#FF0000", "#000000", "#FFFFFF"),
}

FILES = ("HelixGraphiteFern.colors", "HelixGraphiteFern.colorscheme", "HelixGraphiteFern.profile", "wallpaper.svg", "waybar.css", "mako.conf", "fuzzel.ini", "steam.css")
BASE = PALETTES["fern"]


def rgb(value: str) -> str:
    return ",".join(str(int(value[index:index + 2], 16)) for index in (1, 3, 5))


for key, palette in PALETTES.items():
    destination = OUTPUT / key
    destination.mkdir(parents=True, exist_ok=True)
    for filename in FILES:
        text = (SOURCE / filename).read_text(encoding="utf-8")
        for old, new in zip(BASE[1:], palette[1:]):
            text = text.replace(old, new).replace(old.lower(), new.lower())
            text = text.replace(rgb(old), rgb(new)).replace(rgb(old).replace(",", ", "), rgb(new).replace(",", ", "))
        scheme = "HelixGraphite" + palette[0].replace(" ", "")
        text = text.replace("HelixGraphiteFern", scheme)
        text = text.replace("Helix Graphite Fern", f"Helix Graphite {palette[0]}")
        output_name = filename.replace("HelixGraphiteFern", scheme)
        (destination / output_name).write_text(text, encoding="utf-8")
    ghostty = GHOSTTY_PROFILE.read_text(encoding="utf-8")
    for old, new in zip(BASE[1:], palette[1:]):
        ghostty = ghostty.replace(old, new).replace(old.lower(), new.lower())
    (destination / "ghostty.ghostty").write_text(ghostty, encoding="utf-8")

# GTK stays maintained Breeze-Dark for every member of the family.
for filename in ("gtk-3.0-settings.ini", "gtk-4.0-settings.ini"):
    shutil.copy2(SOURCE / filename, OUTPUT / filename)
