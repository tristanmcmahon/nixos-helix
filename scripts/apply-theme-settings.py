#!/usr/bin/env python3
"""Merge Helix Graphite + Fern-owned keys without discarding user settings."""

import argparse
import configparser
import json
import os
import pathlib
import re
import tempfile


def atomic_write(destination: pathlib.Path, text: str) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=destination.parent, prefix=f".{destination.name}.", text=True
    )
    temporary = pathlib.Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, destination)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def merge_ini(source: pathlib.Path, destination: pathlib.Path) -> None:
    source_text = source.read_text(encoding="utf-8")
    destination_text = destination.read_text(encoding="utf-8") if destination.exists() else ""
    for name, text in (("managed source", source_text), (str(destination), destination_text)):
        parser = configparser.ConfigParser(strict=True)
        try:
            parser.read_string(text)
        except configparser.Error as error:
            raise ValueError(f"invalid INI in {name}: {error}") from error

    owned = {}
    section = None
    for raw_line in source_text.splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif section and line and not line.startswith(('#', ';')) and "=" in line:
            key, value = line.split("=", 1)
            owned[(section, key.strip())] = value.strip()

    lines = destination_text.splitlines()
    output = []
    seen = set()
    section = None
    for index, raw_line in enumerate(lines):
        stripped = raw_line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if section:
                for (owned_section, key), value in owned.items():
                    if owned_section == section and (owned_section, key) not in seen:
                        output.append(f"{key}={value}")
                        seen.add((owned_section, key))
            section = stripped[1:-1]
        if section and stripped and not stripped.startswith(('#', ';')) and "=" in stripped:
            key = stripped.split("=", 1)[0].strip()
            owned_key = (section, key)
            if owned_key in owned:
                output.append(f"{key}={owned[owned_key]}")
                seen.add(owned_key)
                continue
        output.append(raw_line)

        if index == len(lines) - 1 and section:
            for (owned_section, key), value in owned.items():
                if owned_section == section and (owned_section, key) not in seen:
                    output.append(f"{key}={value}")
                    seen.add((owned_section, key))

    for (owned_section, key), value in owned.items():
        if (owned_section, key) in seen:
            continue
        if output and output[-1] != "":
            output.append("")
        if f"[{owned_section}]" not in output:
            output.append(f"[{owned_section}]")
        output.append(f"{key}={value}")

    atomic_write(destination, "\n".join(output).rstrip() + "\n")


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
            "workbench.colorTheme": "Default Dark Modern",
            "workbench.preferredDarkColorTheme": "Default Dark Modern",
        }
    )
    colors = settings.get("workbench.colorCustomizations", {})
    if not isinstance(colors, dict):
        colors = {}
    colors.update(
        {
            "activityBar.background": "#181C19",
            "activityBar.foreground": "#E4E8E5",
            "activityBarBadge.background": "#315E3E",
            "activityBarBadge.foreground": "#E4E8E5",
            "editor.background": "#0B0D0C",
            "editor.foreground": "#E4E8E5",
            "editorGroupHeader.tabsBackground": "#181C19",
            "focusBorder": "#67B87A",
            "list.activeSelectionBackground": "#315E3E",
            "list.activeSelectionForeground": "#E4E8E5",
            "panel.background": "#232824",
            "sideBar.background": "#232824",
            "statusBar.background": "#303832",
            "statusBar.foreground": "#E4E8E5",
            "titleBar.activeBackground": "#181C19",
            "titleBar.activeForeground": "#E4E8E5",
            "titleBar.inactiveBackground": "#0B0D0C",
            "titleBar.inactiveForeground": "#AEB8B1",
        }
    )
    settings["workbench.colorCustomizations"] = colors
    atomic_write(destination, json.dumps(settings, indent=2, sort_keys=True) + "\n")


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
