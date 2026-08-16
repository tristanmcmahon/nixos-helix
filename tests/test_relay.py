import json
from pathlib import Path
import requests

import pytest

from tools import relay_to_ollama as relay


def test_schema_valid_example(tmp_path, monkeypatch):
    example = Path("examples/task-example.json")
    data = json.loads(example.read_text())
    schema = json.loads(Path("gwen-schema.json").read_text())
    # Should validate without raising
    from jsonschema import validate

    validate(instance=data, schema=schema)


def test_ollama_retry(monkeypatch, requests_mock):
    example = Path("examples/task-example.json")
    data = json.loads(example.read_text())

    # Simulate two 500 responses followed by a 200
    def responder(request, context):
        # rotate through a sequence stored on the adapter
        seq = getattr(responder, "seq", 0)
        responder.seq = seq + 1
        if seq < 2:
            context.status_code = 500
            return "error"
        context.status_code = 200
        return {"result": "ok"}

    requests_mock.post(relay.OLLUAMA_URL, json=responder)

    # Call call_ollama directly
    r = relay.call_ollama("hello", model="helix-qwen:latest", attempts=3)
    assert r.get("ok") is True
