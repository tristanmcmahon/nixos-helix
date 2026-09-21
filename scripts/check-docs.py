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

# Cross-file facts that have historically drifted as Helix evolved.
readme = (root / "README.md").read_text(encoding="utf-8")
profiles = (root / "docs/profiles.md").read_text(encoding="utf-8")
llm = (root / "profiles/local-llm.nix").read_text(encoding="utf-8")

if "Home Manager,\nflakes, Home Manager" in readme:
    failures.append("README.md: duplicated flakes/Home Manager wording")

model_match = re.search(r"desiredModels = \[(.*?)\n  \];", llm, re.DOTALL)
if model_match:
    models = re.findall(r'"([^"]+)"', model_match.group(1))
    missing = [model for model in models if f"`{model}`" not in profiles]
    if missing:
        failures.append(
            "docs/profiles.md: missing declared Ollama models: " + ", ".join(missing)
        )
    declared_word = {4: "four", 5: "five"}.get(len(models), str(len(models)))
    if f"all {declared_word} declared tags" not in profiles:
        failures.append(
            f"docs/profiles.md: Ollama helper count does not match {len(models)} models"
        )
else:
    failures.append("profiles/local-llm.nix: could not parse desiredModels")

context_match = re.search(r'OLLAMA_CONTEXT_LENGTH\s*=\s*"([0-9]+)"', llm)
if context_match and f"OLLAMA_CONTEXT_LENGTH={context_match.group(1)}" not in profiles:
    failures.append("docs/profiles.md: Ollama context length drifted from configuration")

if "Gamescope, and custom Proton tooling have not been added" in profiles:
    failures.append("docs/profiles.md: stale gaming-tool absence statement")

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)
