#!/usr/bin/env python3
"""Merge Helix Abyss-owned keys without discarding unrelated user settings."""

import argparse
import json
import pathlib
import re


def merge_ini(source: pathlib.Path, destination: pathlib.Path) -> None:
    owned = {}
    section = None
    for raw_line in source.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif section and line and not line.startswith(('#', ';')) and "=" in line:
            key, value = line.split("=", 1)
            owned[(section, key.strip())] = value.strip()

    lines = destination.read_text(encoding="utf-8").splitlines() if destination.exists() else []
    output = []
    seen = set()
    section = None
    for raw_line in lines:
        stripped = raw_line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
        if section and stripped and not stripped.startswith(('#', ';')) and "=" in stripped:
            key = stripped.split("=", 1)[0].strip()
            owned_key = (section, key)
            if owned_key in owned:
                output.append(f"{key}={owned[owned_key]}")
                seen.add(owned_key)
                continue
        output.append(raw_line)

    for (owned_section, key), value in owned.items():
        if (owned_section, key) in seen:
            continue
        if output and output[-1] != "":
            output.append("")
        if f"[{owned_section}]" not in output:
            output.append(f"[{owned_section}]")
        output.append(f"{key}={value}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(output).rstrip() + "\n", encoding="utf-8")


def parse_jsonc(text: str) -> dict:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r"(^|\s)//.*$", r"\1", text, flags=re.MULTILINE)
    text = re.sub(r",\s*([}\]])", r"\1", text)
    value = json.loads(text or "{}")
    if not isinstance(value, dict):
        raise ValueError("VS Code settings must contain a JSON object")
    return value


def merge_vscode(destination: pathlib.Path) -> None:
    settings = parse_jsonc(destination.read_text(encoding="utf-8")) if destination.exists() else {}
    settings.update(
        {
            "window.autoDetectColorScheme": False,
            "workbench.colorTheme": "Abyss",
            "workbench.preferredDarkColorTheme": "Abyss",
        }
    )
    colors = settings.get("workbench.colorCustomizations", {})
    if not isinstance(colors, dict):
        colors = {}
    colors.update(
        {
            "activityBar.background": "#080A0D",
            "editorGroupHeader.tabsBackground": "#0B0E12",
            "panel.background": "#0B0E12",
            "sideBar.background": "#080A0D",
            "statusBar.background": "#10141A",
            "titleBar.activeBackground": "#080A0D",
            "titleBar.activeForeground": "#E6EAF0",
        }
    )
    settings["workbench.colorCustomizations"] = colors
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    ini = subparsers.add_parser("merge-ini")
    ini.add_argument("source", type=pathlib.Path)
    ini.add_argument("destination", type=pathlib.Path)
    vscode = subparsers.add_parser("merge-vscode")
    vscode.add_argument("destination", type=pathlib.Path)
    args = parser.parse_args()
    if args.command == "merge-ini":
        merge_ini(args.source, args.destination)
    else:
        merge_vscode(args.destination)


if __name__ == "__main__":
    main()
