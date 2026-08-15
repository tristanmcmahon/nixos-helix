#!/usr/bin/env python3

import configparser
import importlib.util
import json
import pathlib
import sys
import tempfile
import xml.etree.ElementTree as element_tree

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("theme_settings", ROOT / "scripts/apply-theme-settings.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

colors_path = ROOT / "config/theme/HelixGraphiteFern.colors"
colors = configparser.ConfigParser()
colors.optionxform = str
colors.read(colors_path)
required_groups = {
    "ColorEffects:Disabled",
    "ColorEffects:Inactive",
    "Colors:Button",
    "Colors:Complementary",
    "Colors:Header",
    "Colors:Selection",
    "Colors:Tooltip",
    "Colors:View",
    "Colors:Window",
    "General",
    "WM",
}
assert required_groups.issubset(colors.sections())
for section in colors.sections():
    for key, value in colors[section].items():
        if key.startswith(("Background", "Decoration", "Foreground")) or key.endswith(
            ("Background", "Blend", "Foreground")
        ):
            channels = value.split(",")
            assert len(channels) == 3 and all(0 <= int(channel) <= 255 for channel in channels)
assert colors["Colors:Window"]["BackgroundNormal"] == "24,28,25"
assert colors["Colors:View"]["BackgroundNormal"] == "11,13,12"
assert colors["Colors:Selection"]["BackgroundNormal"] == "49,94,62"

wallpaper = ROOT / "config/theme/wallpaper.svg"
element_tree.parse(wallpaper)
wallpaper_text = wallpaper.read_text(encoding="utf-8")
assert "http://www.w3.org/2000/svg" in wallpaper_text
assert "href=" not in wallpaper_text and "url(http" not in wallpaper_text

for gtk_version in ("3.0", "4.0"):
    gtk_settings = configparser.ConfigParser()
    gtk_settings.read(ROOT / f"config/theme/gtk-{gtk_version}-settings.ini")
    assert gtk_settings["Settings"]["gtk-theme-name"] == "Breeze-Dark"
    assert gtk_settings["Settings"]["gtk-application-prefer-dark-theme"] == "true"

waybar = (ROOT / "config/theme/waybar.css").read_text(encoding="utf-8")
assert waybar.count("{") == waybar.count("}") and "#232824" in waybar

mako = (ROOT / "config/theme/mako.conf").read_text(encoding="utf-8")
for key in ("background-color", "text-color", "border-color", "default-timeout"):
    assert f"{key}=" in mako

fuzzel = configparser.ConfigParser()
fuzzel.read(ROOT / "config/theme/fuzzel.ini")
assert {"main", "colors", "border"}.issubset(fuzzel.sections())
for key in ("background", "text", "input", "selection", "border"):
    assert len(fuzzel["colors"][key]) == 8

steam = (ROOT / "config/theme/steam.css").read_text(encoding="utf-8")
assert steam.count("{") == steam.count("}")
for value in ("11, 13, 12", "24, 28, 25", "35, 40, 36", "103, 184, 122"):
    assert value in steam


with tempfile.TemporaryDirectory() as temporary_directory:
    temporary = pathlib.Path(temporary_directory)
    source = ROOT / "config/theme/gtk-3.0-settings.ini"
    fixtures = {
        "absent": None,
        "settings": "[Settings]\ngtk-theme-name=Old\n",
        "settings-first": "[Settings]\nunrelated-key=preserved\n[Other]\nvalue=kept\n",
        "settings-last": "[Other]\nvalue=kept\n[Settings]\nunrelated-key=preserved\n",
        "missing-settings": "[Other]\nvalue=kept\n",
        "comments": "# retained\n[Settings]\n; retained too\nunrelated-key=preserved\n",
    }
    for name, initial in fixtures.items():
        gtk = temporary / f"{name}.ini"
        if initial is not None:
            gtk.write_text(initial, encoding="utf-8")
        MODULE.merge_ini(source, gtk)
        first_result = gtk.read_text(encoding="utf-8")
        MODULE.merge_ini(source, gtk)
        assert gtk.read_text(encoding="utf-8") == first_result
        parsed = configparser.ConfigParser()
        parsed.read(gtk)
        assert parsed["Settings"]["gtk-theme-name"] == "Breeze-Dark"
        if "unrelated-key" in first_result:
            assert parsed["Settings"]["unrelated-key"] == "preserved"
        if "[Other]" in first_result:
            assert parsed["Other"]["value"] == "kept"
        assert first_result.count("[Settings]") == 1

    malformed = temporary / "malformed.ini"
    malformed_text = "[Settings\ngtk-theme-name=Old\n"
    malformed.write_text(malformed_text, encoding="utf-8")
    try:
        MODULE.merge_ini(source, malformed)
    except ValueError:
        pass
    else:
        raise AssertionError("malformed INI was accepted")
    assert malformed.read_text(encoding="utf-8") == malformed_text

    vscode = temporary / "settings.json"
    vscode.write_text('{\n  // retain the setting value\n  "editor.fontSize": 17,\n}\n', encoding="utf-8")
    MODULE.merge_vscode(vscode)
    first_vscode_result = vscode.read_text(encoding="utf-8")
    MODULE.merge_vscode(vscode)
    assert vscode.read_text(encoding="utf-8") == first_vscode_result
    settings = json.loads(vscode.read_text(encoding="utf-8"))
    assert settings["editor.fontSize"] == 17
    assert settings["workbench.colorTheme"] == "Default Dark Modern"
    assert settings["workbench.colorCustomizations"]["editor.background"] == "#0B0D0C"
    assert settings["workbench.colorCustomizations"]["sideBar.background"] == "#232824"

print("Theme settings merge fixtures passed.")
