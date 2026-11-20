#!/usr/bin/env python3
"""Offline parser and command-mock tests; never contact actual GPU or Nix store."""
import importlib.util
import json
from pathlib import Path
import sys
from unittest.mock import patch

source = Path(__file__).resolve().parents[1] / "scripts/helix-benchmark.py"
spec = importlib.util.spec_from_file_location("helix_benchmark", source)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

assert module._parse_duration_seconds(
    "Startup finished in 3.5s (kernel) + 8.125s (userspace) = 11.625s\n"
) == 11.625
assert module._parse_duration_seconds("Startup finished in 125ms = 125ms") == 0.125
assert module._parse_duration_seconds("failed or unavailable") is None

assert module._parse_pressure_avg10("some avg10=0.42 avg60=0.1 total=1\nfull avg10=0.00") == 0.42
assert module._parse_pressure_avg10("full avg10=0.42") is None

closure = {"/nix/store/fake-system": {"narSize": 1000, "closureSize": 8000000000}}
assert module._parse_closure_bytes(json.dumps(closure)) == 8000000000
assert module._parse_closure_bytes('{"path": {"narSize": 200}}') is None
assert module._parse_closure_bytes("invalid") is None

def fake_command(args, **kwargs):
    tool = args[0]
    if tool == "systemd-analyze" and args[1] == "time":
        return "Startup finished in 4.00s (kernel) + 12.30s (userspace) = 16.30s"
    if tool == "systemd-analyze" and args[1] == "blame":
        return "12.300s first.service\n 5.000s second.service"
    if tool == "nix":
        return json.dumps(closure)
    if tool == "nvidia-smi":
        return "620.70.06, 32.40, 1, 410"
    raise AssertionError(args)

with patch.object(module, "_read_command", side_effect=fake_command):
    result = module.run_profile()
assert result.category == "profile"
assert result.metrics["boot_seconds"] == 16.3
assert result.metrics["system_closure_bytes"] == 8000000000
assert result.metrics["gpu"]["power_watts"] == 32.4
assert result.metrics["gpu"]["driver"] == "620.70.06"
assert len(result.metrics["longest_starting_units"]) == 2

print("Performance profile parser and capture mocks: PASS")
