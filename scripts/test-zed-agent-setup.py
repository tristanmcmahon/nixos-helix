#!/usr/bin/env python3

import contextlib
import importlib.util
import io
import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("zed_agent_setup", ROOT / "scripts/helix-zed-agent-setup.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

# JSONC stripping must leave comment-like and comma-like text inside strings.
assert json.loads(MODULE.strip_jsonc('{"url": "https://x//y", "s": "a,}", /* c */ "n": [1, 2,],}')) == {
    "url": "https://x//y",
    "s": "a,}",
    "n": [1, 2],
}
assert json.loads(MODULE.strip_jsonc('{"q": "say \\"hi\\" // no"} // tail')) == {"q": 'say "hi" // no'}

with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()):
    settings = pathlib.Path(directory) / "zed" / "settings.json"

    # A missing file is created without a backup.
    assert MODULE.configure(settings) is None
    created = json.loads(settings.read_text())
    assert created == {"agent_servers": {"Claude Code": MODULE.AGENT}}

    # Re-running on a configured file changes nothing and creates no backup.
    assert MODULE.configure(settings) is None
    assert list(settings.parent.glob("*.bak")) == []

    # Real Zed settings are JSONC; other keys and agents are preserved and
    # every run keeps its own backup of the original bytes.
    original = '// user settings\n{\n  "theme": "One Dark", // inline\n  "agent_servers": {"Other": {"command": "x"},},\n}\n'
    settings.write_text(original)
    settings.chmod(0o600)
    first_backup = MODULE.configure(settings)
    assert first_backup is not None and first_backup.read_text() == original
    updated = json.loads(settings.read_text())
    assert updated["theme"] == "One Dark"
    assert updated["agent_servers"]["Other"] == {"command": "x"}
    assert updated["agent_servers"]["Claude Code"]["command"] == "claude-agent-acp"
    assert "/nix/store" not in settings.read_text()
    assert settings.stat().st_mode & 0o777 == 0o600

    settings.write_text('{"agent_servers": {}}')
    second_backup = MODULE.configure(settings)
    assert second_backup is not None and second_backup != first_backup
    assert first_backup.read_text() == original

    # Unparseable or wrongly shaped settings are refused untouched.
    for bad in ['{"theme": ', "[]", '{"agent_servers": []}']:
        settings.write_text(bad)
        try:
            MODULE.configure(settings)
        except SystemExit:
            pass
        else:
            raise AssertionError(f"accepted {bad!r}")
        assert settings.read_text() == bad
    assert list(settings.parent.glob(".settings.*")) == []

print("Zed agent setup helper behaves safely.")
