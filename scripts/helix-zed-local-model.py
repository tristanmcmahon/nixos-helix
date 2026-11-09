#!/usr/bin/env python3
"""Opt-in Zed Agent/Ollama setup; leaves ACP agents and MCP servers alone.

Run from the nixos-helix checkout. User settings are mutable, never Nix-owned.
"""

import argparse
import datetime
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
from urllib.error import URLError
from urllib.request import urlopen

OLLAMA_URL = "http://127.0.0.1:11434"
SUPPORTED_URLS = {OLLAMA_URL, "http://localhost:11434"}


def strip_jsonc(text):
    """Reuse the existing Helix JSONC reader; no extra Python dependencies."""
    path = Path(__file__).with_name("helix-zed-agent-setup.py")
    spec = importlib.util.spec_from_file_location("helix_zed_agent_setup", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load Helix Zed parser: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.strip_jsonc(text)


def installed_models():
    try:
        with urlopen(OLLAMA_URL + "/api/tags", timeout=5) as response:
            payload = json.load(response)
    except (OSError, ValueError, URLError) as exc:
        raise ValueError(f"Ollama at {OLLAMA_URL} is unavailable: {exc}") from exc
    return {model.get("name") for model in payload.get("models", []) if isinstance(model, dict)}


def target_settings(settings, model, context):
    """Return a copy with only the Zed Agent model and Ollama options changed."""
    if not isinstance(settings, dict):
        raise ValueError("Zed settings root is not an object")
    updated = json.loads(json.dumps(settings))
    agent = updated.setdefault("agent", {})
    if not isinstance(agent, dict):
        raise ValueError("agent settings are not an object")
    models = updated.setdefault("language_models", {})
    if not isinstance(models, dict):
        raise ValueError("language_models settings are not an object")
    ollama = models.setdefault("ollama", {})
    if not isinstance(ollama, dict):
        raise ValueError("language_models.ollama is not an object")
    existing_url = ollama.get("api_url", OLLAMA_URL)
    if existing_url not in SUPPORTED_URLS:
        raise ValueError(f"Refusing to override non-local Ollama URL: {existing_url!r}")
    ollama.setdefault("api_url", OLLAMA_URL)
    ollama["context_window"] = context
    agent["default_model"] = {"provider": "ollama", "model": model}
    return updated


def load_settings(path):
    if path.is_symlink():
        raise ValueError(f"Refusing symlink settings file: {path}")
    if path.exists() and not path.is_file():
        raise ValueError(f"Not a regular file: {path}")
    original = path.read_text(encoding="utf-8") if path.exists() else None
    try:
        settings = json.loads(strip_jsonc(original)) if original and original.strip() else {}
    except (ValueError, json.JSONDecodeError) as exc:
        raise ValueError(f"Refusing invalid Zed settings: {exc}") from exc
    return original, settings


def configure(path, *, model="gpt-oss:20b", context=32768, execute=False, models=None):
    if context < 4096 or context > 131072:
        raise ValueError("context must be between 4096 and 131072")
    available = models if models is not None else installed_models()
    if model not in available:
        raise ValueError(f"Model {model!r} is not installed in Ollama; no changes made")
    original, current = load_settings(path)
    updated = target_settings(current, model, context)
    if current == updated:
        return "PASS: Zed Agent already configured for local Ollama; no changes"
    if not execute:
        return f"PLAN: set Zed Agent default to Ollama {model}, context {context}; no changes"

    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if original is not None:
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        backup = path.with_name(f"{path.name}.local-model-backup-{stamp}-{os.getpid()}")
        descriptor = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(original)
    else:
        backup = None

    fd, temp = tempfile.mkstemp(prefix=".local-model-", dir=path.parent)
    try:
        if path.exists():
            os.fchmod(fd, stat.S_IMODE(path.stat().st_mode))
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(updated, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        if (path.read_text(encoding="utf-8") if path.exists() else None) != original:
            raise ValueError("Zed settings changed concurrently; refusing to replace")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return f"PASS: Zed Agent configured for Ollama {model}; backup: {backup or 'not needed'}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Inspect only (default)")
    mode.add_argument("--execute", action="store_true", help="Backup and update Zed user settings")
    parser.add_argument("--model", default="gpt-oss:20b")
    parser.add_argument("--context", type=int, default=32768)
    args = parser.parse_args()
    home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    path = home / "zed" / "settings.json"
    try:
        print(configure(path, model=args.model, context=args.context, execute=args.execute))
        print("INFO: Zed Agent and Claude/OpenClaw ACP are separate; existing hamLLM MCP config is unchanged")
        print("INFO: A Zed Agent profile can disable MCP tools; select a profile that permits hamllm")
    except (ValueError, OSError, UnicodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
