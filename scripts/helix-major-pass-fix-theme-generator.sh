#!/usr/bin/env bash

set -Eeuo pipefail

repo=${HOME}/Projects/nixos-helix
cd "$repo"

branch=$(git branch --show-current)
case $branch in
upgrade/helix-major-pass-*) ;;
*)
  printf 'Refusing to repair outside a helix major-pass branch: %s\n' "$branch" >&2
  exit 1
  ;;
esac

printf '=== REPAIR THEME GENERATOR INPUTS ===\n'
python3 <<'PY'
from pathlib import Path
import re

# 1. Make the Ghostty profile an explicit generator input.
generator = Path("scripts/generate-theme-family.py")
text = generator.read_text(encoding="utf-8")

old_args = '''SOURCE = pathlib.Path(sys.argv[1])
OUTPUT = pathlib.Path(sys.argv[2])'''
new_args = '''if len(sys.argv) != 4:
    raise SystemExit("usage: generate-theme-family.py THEME_SOURCE GHOSTTY_PROFILE OUTPUT")

SOURCE = pathlib.Path(sys.argv[1])
GHOSTTY_PROFILE = pathlib.Path(sys.argv[2])
OUTPUT = pathlib.Path(sys.argv[3])'''

if old_args in text:
    text = text.replace(old_args, new_args, 1)
elif "GHOSTTY_PROFILE = pathlib.Path(sys.argv[2])" not in text:
    raise SystemExit("generate-theme-family.py argument layout is not the expected generated form")

old_ghostty = '(SOURCE.parent / "ghostty/profiles/main.ghostty").read_text(encoding="utf-8")'
new_ghostty = 'GHOSTTY_PROFILE.read_text(encoding="utf-8")'
if old_ghostty in text:
    text = text.replace(old_ghostty, new_ghostty, 1)
elif new_ghostty not in text:
    raise SystemExit("generate-theme-family.py Ghostty lookup is not the expected generated form")

generator.write_text(text, encoding="utf-8")

# 2. Update the Python fixture to pass the canonical Ghostty profile explicitly.
test = Path("scripts/test-theme-settings.py")
text = test.read_text(encoding="utf-8")
old = '[sys.executable, str(ROOT / "scripts/generate-theme-family.py"), str(ROOT / "config/theme"), generated_directory]'
new = '[sys.executable, str(ROOT / "scripts/generate-theme-family.py"), str(ROOT / "config/theme"), str(ROOT / "config/ghostty/profiles/main.ghostty"), generated_directory]'
if old in text:
    text = text.replace(old, new, 1)
elif 'str(ROOT / "config/ghostty/profiles/main.ghostty")' not in text:
    raise SystemExit("test-theme-settings.py generator invocation is not the expected generated form")
test.write_text(text, encoding="utf-8")

# 3. Update the Nix derivation invocation. Keep this deliberately structural:
# locate the command mentioning generate-theme-family.py and insert the exact
# canonical Ghostty profile before $out. This makes Nix carry the profile into
# the store as a real derivation input instead of relying on source-tree layout.
theme = Path("desktop/theme.nix")
text = theme.read_text(encoding="utf-8")
if "generate-theme-family.py" not in text:
    raise SystemExit("desktop/theme.nix has no theme-family generator invocation")

if "config/ghostty/profiles/main.ghostty" not in text:
    lines = text.splitlines(keepends=True)
    changed = False
    for i, line in enumerate(lines):
        if "generate-theme-family.py" not in line:
            continue
        # Common generated one-line form.
        if "$out" in line:
            lines[i] = line.replace(" $out", " ${../config/ghostty/profiles/main.ghostty} $out", 1)
            changed = True
            break
        # Multi-line command: find the next $out argument nearby.
        for j in range(i + 1, min(i + 8, len(lines))):
            if "$out" in lines[j]:
                indent = re.match(r"\s*", lines[j]).group(0)
                lines.insert(j, f"{indent}${{../config/ghostty/profiles/main.ghostty}} \\\n")
                changed = True
                break
        if changed:
            break
    if not changed:
        raise SystemExit("could not locate the theme-family generator output argument in desktop/theme.nix")
    text = "".join(lines)
    theme.write_text(text, encoding="utf-8")
else:
    print("desktop/theme.nix already carries the canonical Ghostty profile input")

print("Theme generator now receives the canonical Ghostty profile explicitly.")
PY

nixfmt desktop/theme.nix
python3 -m py_compile scripts/generate-theme-family.py scripts/test-theme-settings.py
git diff --check

printf '\n=== FOCUSED THEME FIXTURE ===\n'
python3 scripts/test-theme-settings.py

printf '\n=== RESUME MAJOR PASS ===\n'
bash <(git show origin/main:scripts/helix-major-pass-resume.sh)
