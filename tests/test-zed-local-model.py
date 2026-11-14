#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile

spec = importlib.util.spec_from_file_location(
    "local_setup", Path(__file__).resolve().parents[1] / "scripts/helix-zed-local-model.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "zed/settings.json"
    path.parent.mkdir()
    original = '{"theme": "One Dark", "context_servers": {"hamllm": {"command": "hamllm"}}, "agent_servers": {"Claude Code": {"command": "claude-agent-acp"}}}'
    path.write_text(original)
    assert module.configure(path, execute=False, models={"gpt-oss:20b"}).startswith("PLAN:")
    assert path.read_text() == original
    assert module.configure(path, execute=True, models={"gpt-oss:20b"}).startswith("PASS:")
    data = json.loads(path.read_text())
    assert data["agent"]["default_model"] == {"provider": "ollama", "model": "gpt-oss:20b"}
    assert data["language_models"]["ollama"]["context_window"] == 32768
    assert data["context_servers"]["hamllm"]["command"] == "hamllm"
    assert data["agent_servers"]["Claude Code"]["command"] == "claude-agent-acp"
    backups = list(path.parent.glob("settings.json.local-model-backup-*"))
    assert len(backups) == 1 and backups[0].read_text() == original
    assert module.configure(path, execute=True, models={"gpt-oss:20b"}).startswith("PASS:")
    assert len(list(path.parent.glob("settings.json.local-model-backup-*"))) == 1

    try:
        module.configure(path, execute=True, models={"nonexistent"})
    except ValueError as exc:
        assert "not installed" in str(exc)
    else:
        raise AssertionError("accepted missing model")

    # JSONC is parsed without mistaking URL slashes for comments.
    path.write_text('// comment\n{"theme": "https://host/path", "context_servers": {"hamllm": {"command": "hamllm",},},}')
    assert module.configure(path, execute=True, models={"gpt-oss:20b"}).startswith("PASS:")
    assert json.loads(path.read_text())["theme"] == "https://host/path"
    assert "// comment" in sorted(path.parent.glob("settings.json.local-model-backup-*"))[-1].read_text()
    path.write_text('{"agent": []}')
    try:
        module.configure(path, execute=True, models={"gpt-oss:20b"})
    except ValueError as exc:
        assert "not an object" in str(exc)
    else:
        raise AssertionError("accepted invalid agent")

    path.unlink()
    path.symlink_to(backups[0])
    try:
        module.configure(path, execute=True, models={"gpt-oss:20b"})
    except ValueError as exc:
        assert "symlink" in str(exc)
    else:
        raise AssertionError("accepted symlink")

print("PASS: local Zed Ollama setup safeguards")
