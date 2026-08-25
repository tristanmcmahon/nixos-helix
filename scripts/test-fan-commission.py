#!/usr/bin/env python3

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location(
    "fan_commission", ROOT / "scripts/helix-fan-commission.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

devices = [
    {
        "uid": "nct",
        "name": "nct6798",
        "type": "Hwmon",
        "info": {
            "driver_info": {"name": "nct6798"},
            "channels": {
                "fan1": {
                    "label": "CPU Fan",
                    "speed_options": {
                        "fixed_enabled": True,
                        "min_duty": 0,
                        "max_duty": 100,
                    },
                },
                "fan5": {
                    "label": "AIO Pump",
                    "speed_options": {
                        "fixed_enabled": True,
                        "min_duty": 0,
                        "max_duty": 100,
                    },
                },
                "fan7": {
                    "speed_options": {
                        "fixed_enabled": True,
                        "min_duty": 0,
                        "max_duty": 100,
                    },
                },
            },
        },
    },
    {
        "uid": "gpu",
        "name": "NVIDIA GeForce RTX 5080",
        "type": "GPU",
        "info": {
            "driver_info": {"name": "NVML"},
            "channels": {
                "fan1": {"speed_options": {"fixed_enabled": True}}
            },
        },
    },
]
statuses = [
    {
        "uid": "nct",
        "type": "Hwmon",
        "status_history": [
            {
                "temps": [],
                "channels": [
                    {"name": "fan1", "rpm": 850},
                    {"name": "fan5", "rpm": 2600},
                    {"name": "fan7", "rpm": 2800},
                ],
            }
        ],
    }
]

eligible, skipped = MODULE.eligible_channels(devices, statuses)
assert len(eligible) == 1
assert eligible[0].name == "fan1"
assert eligible[0].label == "CPU Fan"
assert any("pump" in reason.lower() for reason in skipped)
assert any("high-speed auxiliary" in reason for reason in skipped)
assert MODULE.profile_uid(eligible[0], "cpu") == MODULE.profile_uid(eligible[0], "cpu")
profile = MODULE.graph_profile(eligible[0], ("cpu", "CPU Temp Tctl"), 35, "cpu")
assert profile["speed_profile"][0] == [30, 35]
assert profile["speed_profile"][-1] == [80, 100]
assert profile["temp_source"] == {"device_uid": "cpu", "temp_name": "CPU Temp Tctl"}
capped_channel = MODULE.Channel("nct", "nct6798", "fan3", "Fan 3", 0, 80)
capped_profile = MODULE.graph_profile(
    capped_channel, ("cpu", "CPU Temp Tctl"), 75, "cpu"
)
assert all(duty <= 80 for _temperature, duty in capped_profile["speed_profile"])

original_median_rpm = MODULE.median_rpm
original_sleep = MODULE.time.sleep
rpm_samples = iter((900, MODULE.HIGH_SPEED_PROTECTION_RPM))
MODULE.median_rpm = lambda _api, _channel, samples=3: next(rpm_samples)
MODULE.time.sleep = lambda _seconds: None


class ProbeAPI:
    def __init__(self):
        self.duties = []

    def manual(self, _device_uid, _channel_name, duty):
        self.duties.append(duty)


probe = ProbeAPI()
try:
    MODULE.test_channel(probe, eligible[0])
except MODULE.ProtectedChannel:
    pass
else:
    raise AssertionError("high-speed auxiliary probe was not protected")
finally:
    MODULE.median_rpm = original_median_rpm
    MODULE.time.sleep = original_sleep
assert probe.duties == [85]


class RestoreAPI:
    def __init__(self):
        self.operations = []

    def reset(self, device_uid, channel_name):
        self.operations.append(("reset", device_uid, channel_name))

    def profile(self, device_uid, channel_name, profile_uid):
        self.operations.append(("profile", device_uid, channel_name, profile_uid))

    def manual(self, device_uid, channel_name, duty):
        self.operations.append(("manual", device_uid, channel_name, duty))

    def pwm(self, device_uid, channel_name, mode):
        self.operations.append(("pwm", device_uid, channel_name, mode))


restore = RestoreAPI()
MODULE.restore_channel(
    restore,
    eligible[0],
    {"channel_name": "fan1", "reset_to_default": True, "_pwm_mode": 2},
)
assert restore.operations == [("reset", "nct", "fan1"), ("pwm", "nct", "fan1", 2)]

print("Automatic fan commissioning fixtures passed.")
