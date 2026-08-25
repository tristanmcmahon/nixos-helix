#!/usr/bin/env python3
"""Safely discover, characterise, and configure Helix's motherboard fans."""

from __future__ import annotations

import argparse
import base64
import getpass
import http.cookiejar
import json
import os
import pathlib
import re
import signal
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import dataclass
from typing import Any

API_URL = "http://127.0.0.1:11987"
EXPECTED_VENDOR = "ASUSTeK COMPUTER INC."
EXPECTED_BOARD = "TUF GAMING X570-PLUS (WI-FI)"
STATE_PATH = pathlib.Path.home() / ".local/state/helix/fan-commissioning.json"
PUMP_PATTERN = re.compile(r"pump|aio|water|liquid", re.IGNORECASE)
GPU_PATTERN = re.compile(r"gpu|nvidia|amdgpu", re.IGNORECASE)
CPU_TEMP_LIMIT = 80.0
HIGH_SPEED_PROTECTION_RPM = 2200
MIN_SWEEP_DUTY = 40
SAMPLE_SECONDS = 1.0


class CommissionError(RuntimeError):
    """A safe, user-facing commissioning failure."""


class ProtectedChannel(CommissionError):
    """A channel that should remain under its original control."""


class AuthenticationError(CommissionError):
    """CoolerControl rejected the supplied credentials."""


class CoolerControlAPI:
    def __init__(self, base_url: str = API_URL) -> None:
        self.base_url = base_url.rstrip("/")
        self.cookies = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.cookies)
        )

    def request(
        self, method: str, path: str, payload: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> Any:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request_headers = {"Accept": "application/json"}
        if body is not None:
            request_headers["Content-Type"] = "application/json"
        if headers:
            request_headers.update(headers)
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=body, headers=request_headers, method=method
        )
        try:
            with self.opener.open(request, timeout=15) as response:
                content = response.read()
                return json.loads(content) if content else None
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            error_type = (
                AuthenticationError if error.code in (401, 403) else CommissionError
            )
            raise error_type(
                f"CoolerControl {method} {path} failed: HTTP {error.code}: {detail}"
            ) from error
        except urllib.error.URLError as error:
            raise CommissionError(
                f"Cannot reach CoolerControl at {self.base_url}: {error.reason}"
            ) from error

    def login(self, password: str | None) -> None:
        password = password or "coolAdmin"
        token = base64.b64encode(f"CCAdmin:{password}".encode()).decode()
        self.request("POST", "/login", headers={"Authorization": f"Basic {token}"})

    @staticmethod
    def channel_path(device_uid: str, channel_name: str, suffix: str) -> str:
        uid = urllib.parse.quote(device_uid, safe="")
        channel = urllib.parse.quote(channel_name, safe="")
        return f"/devices/{uid}/settings/{channel}/{suffix}"

    def devices(self) -> list[dict[str, Any]]:
        return self.request("GET", "/devices")["devices"]

    def statuses(self) -> list[dict[str, Any]]:
        return self.request("POST", "/status", {})["devices"]

    def settings(self, device_uid: str) -> list[dict[str, Any]]:
        uid = urllib.parse.quote(device_uid, safe="")
        return self.request("GET", f"/devices/{uid}/settings")["settings"]

    def manual(self, device_uid: str, channel_name: str, duty: int) -> None:
        path = self.channel_path(device_uid, channel_name, "manual")
        self.request("PUT", path, {"speed_fixed": duty})

    def profile(self, device_uid: str, channel_name: str, profile_uid: str) -> None:
        path = self.channel_path(device_uid, channel_name, "profile")
        self.request("PUT", path, {"profile_uid": profile_uid})

    def pwm(self, device_uid: str, channel_name: str, pwm_mode: int) -> None:
        path = self.channel_path(device_uid, channel_name, "pwm")
        self.request("PUT", path, {"pwm_mode": pwm_mode})

    def reset(self, device_uid: str, channel_name: str) -> None:
        path = self.channel_path(device_uid, channel_name, "reset")
        self.request("PUT", path)

    def profiles(self) -> list[dict[str, Any]]:
        return self.request("GET", "/profiles")["profiles"]

    def upsert_profile(self, profile: dict[str, Any], existing: set[str]) -> None:
        method = "PUT" if profile["uid"] in existing else "POST"
        self.request(method, "/profiles", profile)
        existing.add(profile["uid"])


@dataclass(frozen=True)
class Channel:
    device_uid: str
    device_name: str
    name: str
    label: str
    min_duty: int
    max_duty: int

    @property
    def display_name(self) -> str:
        return f"{self.device_name} · {self.label or self.name}"


def read_text(path: str) -> str:
    try:
        return pathlib.Path(path).read_text(encoding="utf-8").strip()
    except OSError:
        return "unknown"


def board_details() -> dict[str, str]:
    root = "/sys/devices/virtual/dmi/id"
    return {
        "vendor": read_text(f"{root}/board_vendor"),
        "name": read_text(f"{root}/board_name"),
        "version": read_text(f"{root}/board_version"),
    }


def hwmon_devices() -> list[str]:
    devices = []
    for name_path in sorted(pathlib.Path("/sys/class/hwmon").glob("hwmon*/name")):
        try:
            devices.append(name_path.read_text(encoding="utf-8").strip())
        except OSError:
            continue
    return devices


def channel_statuses(statuses: list[dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    result: dict[tuple[str, str], dict[str, Any]] = {}
    for device in statuses:
        history = device.get("status_history") or []
        if not history:
            continue
        for channel in history[-1].get("channels", []):
            result[(device["uid"], channel["name"])] = channel
    return result


def cpu_temperature(statuses: list[dict[str, Any]]) -> float | None:
    temperatures = []
    for device in statuses:
        if device.get("type") != "CPU":
            continue
        history = device.get("status_history") or []
        if history:
            temperatures.extend(
                float(temp["temp"]) for temp in history[-1].get("temps", [])
            )
    return max(temperatures) if temperatures else None


def eligible_channels(
    devices: list[dict[str, Any]], statuses: list[dict[str, Any]]
) -> tuple[list[Channel], list[str]]:
    current = channel_statuses(statuses)
    eligible = []
    skipped = []
    for device in devices:
        if device.get("type") != "Hwmon":
            continue
        info = device.get("info") or {}
        driver = (info.get("driver_info") or {}).get("name") or ""
        identity = f"{device.get('name', '')} {driver}"
        if "nct" not in identity.lower():
            continue
        for name, channel_info in (info.get("channels") or {}).items():
            speed = (channel_info or {}).get("speed_options")
            if not speed or not speed.get("fixed_enabled"):
                continue
            label = (channel_info or {}).get("label") or name
            description = f"{device['name']} · {label}"
            if PUMP_PATTERN.search(description) or GPU_PATTERN.search(description):
                skipped.append(f"{description}: protected by name")
                continue
            status = current.get((device["uid"], name), {})
            rpm = int(status.get("rpm") or 0)
            if rpm <= 0:
                skipped.append(f"{description}: no spinning fan detected")
                continue
            if rpm >= HIGH_SPEED_PROTECTION_RPM:
                skipped.append(
                    f"{description}: {rpm} RPM is protected as a high-speed auxiliary"
                )
                continue
            eligible.append(
                Channel(
                    device_uid=device["uid"],
                    device_name=device["name"],
                    name=name,
                    label=label,
                    min_duty=int(speed.get("min_duty", 0)),
                    max_duty=int(speed.get("max_duty", 100)),
                )
            )
    return eligible, skipped


def median_rpm(api: CoolerControlAPI, channel: Channel, samples: int = 3) -> int:
    rpms = []
    for _ in range(samples):
        statuses = api.statuses()
        temperature = cpu_temperature(statuses)
        if temperature is None:
            raise CommissionError(
                "CPU temperature disappeared; aborting and restoring fan control"
            )
        if temperature >= CPU_TEMP_LIMIT:
            raise CommissionError(
                f"CPU reached {temperature:.1f}°C; aborting and restoring fan control"
            )
        status = channel_statuses(statuses).get((channel.device_uid, channel.name), {})
        rpms.append(int(status.get("rpm") or 0))
        time.sleep(SAMPLE_SECONDS)
    return round(statistics.median(rpms))


def original_settings(
    api: CoolerControlAPI,
    channels: list[Channel],
    statuses: list[dict[str, Any]],
) -> dict[tuple[str, str], dict[str, Any] | None]:
    by_device: dict[str, list[dict[str, Any]]] = {}
    current = channel_statuses(statuses)
    for channel in channels:
        by_device.setdefault(channel.device_uid, api.settings(channel.device_uid))
    snapshot = {}
    for channel in channels:
        setting = next(
            (
                item
                for item in by_device[channel.device_uid]
                if item.get("channel_name") == channel.name
            ),
            None,
        )
        if setting is not None:
            setting = dict(setting)
        else:
            setting = {"channel_name": channel.name, "reset_to_default": True}
        status = current.get((channel.device_uid, channel.name), {})
        setting["_pwm_mode"] = status.get("pwm_mode")
        snapshot[(channel.device_uid, channel.name)] = setting
    return snapshot


def restore_channel(
    api: CoolerControlAPI, channel: Channel, setting: dict[str, Any] | None
) -> None:
    if not setting or setting.get("reset_to_default"):
        api.reset(channel.device_uid, channel.name)
    elif setting.get("profile_uid"):
        api.profile(channel.device_uid, channel.name, setting["profile_uid"])
    elif setting.get("speed_fixed") is not None:
        api.manual(channel.device_uid, channel.name, int(setting["speed_fixed"]))
    else:
        api.reset(channel.device_uid, channel.name)
    if setting and setting.get("_pwm_mode") is not None:
        api.pwm(channel.device_uid, channel.name, int(setting["_pwm_mode"]))


def test_channel(api: CoolerControlAPI, channel: Channel) -> dict[str, Any]:
    baseline = median_rpm(api, channel)
    high_duty = min(channel.max_duty, 85)
    api.manual(channel.device_uid, channel.name, high_duty)
    time.sleep(6)
    high_rpm = median_rpm(api, channel)
    if high_rpm < 250:
        raise CommissionError(f"{channel.display_name} did not spin at {high_duty}%")
    if high_rpm >= HIGH_SPEED_PROTECTION_RPM:
        raise ProtectedChannel(
            f"{channel.display_name}: {high_rpm} RPM at {high_duty}% is protected "
            "as a high-speed auxiliary"
        )

    lowest_stable = high_duty
    stall_duty = None
    lower_bound = max(channel.min_duty, MIN_SWEEP_DUTY)
    for duty in range(min(60, high_duty), lower_bound - 1, -5):
        api.manual(channel.device_uid, channel.name, duty)
        time.sleep(5)
        rpm = median_rpm(api, channel, samples=2)
        stable_threshold = max(250, round(high_rpm * 0.18))
        if rpm < stable_threshold:
            stall_duty = duty
            api.manual(channel.device_uid, channel.name, min(channel.max_duty, 100))
            time.sleep(6)
            break
        lowest_stable = duty

    safe_floor = min(channel.max_duty, max(channel.min_duty, lowest_stable + 10))
    return {
        "device_uid": channel.device_uid,
        "device": channel.device_name,
        "channel": channel.name,
        "label": channel.label,
        "baseline_rpm": baseline,
        "high_duty": high_duty,
        "high_rpm": high_rpm,
        "lowest_stable_duty": lowest_stable,
        "stall_duty": stall_duty,
        "safe_floor": safe_floor,
    }


def profile_uid(channel: Channel, kind: str) -> str:
    key = f"helix:{channel.device_uid}:{channel.name}:{kind}"
    return str(uuid.uuid5(uuid.NAMESPACE_URL, key))


def graph_profile(
    channel: Channel,
    source: tuple[str, str],
    floor: int,
    kind: str,
) -> dict[str, Any]:
    maximum = min(channel.max_duty, 100)
    floor = min(floor, maximum)
    curve = [
        [30, floor],
        [50, floor],
        [60, min(maximum, max(floor + 10, 50))],
        [70, min(maximum, max(floor + 25, 75))],
        [80, maximum],
    ]
    return {
        "uid": profile_uid(channel, kind),
        "p_type": "Graph",
        "name": f"Helix {channel.label} · {kind.upper()}",
        "speed_fixed": None,
        "speed_profile": curve,
        "temp_source": {"device_uid": source[0], "temp_name": source[1]},
        "temp_min": 20,
        "temp_max": 100,
        "function_uid": "0",
        "member_profile_uids": [],
        "mix_function_type": None,
        "offset_profile": None,
    }


def choose_temperature_sources(
    devices: list[dict[str, Any]],
) -> tuple[tuple[str, str], tuple[str, str] | None]:
    cpu_source = None
    gpu_source = None
    for device in devices:
        temps = list(((device.get("info") or {}).get("temps") or {}).keys())
        if device.get("type") == "CPU" and temps:
            preferred = next(
                (name for name in temps if re.search(r"tctl|package|cpu temp", name, re.I)),
                temps[0],
            )
            cpu_source = (device["uid"], preferred)
        elif device.get("type") == "GPU" and temps and gpu_source is None:
            preferred = next((name for name in temps if "gpu temp" in name.lower()), temps[0])
            gpu_source = (device["uid"], preferred)
    if cpu_source is None:
        raise CommissionError("CoolerControl did not expose a CPU temperature source")
    return cpu_source, gpu_source


def apply_curves(
    api: CoolerControlAPI,
    devices: list[dict[str, Any]],
    channels: list[Channel],
    results: list[dict[str, Any]],
) -> None:
    cpu_source, gpu_source = choose_temperature_sources(devices)
    existing = {profile["uid"] for profile in api.profiles()}
    results_by_channel = {
        (result["device_uid"], result["channel"]): result for result in results
    }
    for channel in channels:
        result = results_by_channel[(channel.device_uid, channel.name)]
        floor = int(result["safe_floor"])
        cpu_profile = graph_profile(channel, cpu_source, floor, "cpu")
        api.upsert_profile(cpu_profile, existing)
        applied_uid = cpu_profile["uid"]
        if gpu_source is not None:
            gpu_profile = graph_profile(channel, gpu_source, floor, "gpu")
            api.upsert_profile(gpu_profile, existing)
            mix = {
                "uid": profile_uid(channel, "max"),
                "p_type": "Mix",
                "name": f"Helix {channel.label} · CPU/GPU max",
                "speed_fixed": None,
                "speed_profile": None,
                "temp_source": None,
                "temp_min": None,
                "temp_max": None,
                "function_uid": "0",
                "member_profile_uids": [cpu_profile["uid"], gpu_profile["uid"]],
                "mix_function_type": "Max",
                "offset_profile": None,
            }
            api.upsert_profile(mix, existing)
            applied_uid = mix["uid"]
        api.profile(channel.device_uid, channel.name, applied_uid)
        result["applied_profile_uid"] = applied_uid


def write_report(report: dict[str, Any]) -> None:
    try:
        STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
        temporary = STATE_PATH.with_suffix(".tmp")
        temporary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        temporary.replace(STATE_PATH)
    except OSError as error:
        raise CommissionError(f"Cannot write commissioning report: {error}") from error


def report_settings(
    channels: list[Channel],
    snapshot: dict[tuple[str, str], dict[str, Any] | None],
) -> list[dict[str, Any]]:
    return [
        {
            "device_uid": channel.device_uid,
            "device": channel.device_name,
            "channel": channel.name,
            "label": channel.label,
            "setting": snapshot[(channel.device_uid, channel.name)],
        }
        for channel in channels
    ]


def restore_report(api: CoolerControlAPI) -> None:
    board = board_details()
    if board["vendor"] != EXPECTED_VENDOR or board["name"] != EXPECTED_BOARD:
        raise CommissionError("Refusing restore on a machine other than Helix")
    try:
        report = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise CommissionError(f"No commissioning report exists at {STATE_PATH}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise CommissionError(f"Cannot read commissioning report: {error}") from error
    report_board = report.get("board") or {}
    if (
        report_board.get("vendor") != board["vendor"]
        or report_board.get("name") != board["name"]
    ):
        raise CommissionError("Commissioning report belongs to a different board")
    originals = report.get("original_settings") or []
    if not originals:
        raise CommissionError("Commissioning report has no original settings to restore")
    for original in originals:
        channel = Channel(
            device_uid=original["device_uid"],
            device_name=original.get("device", "Nuvoton"),
            name=original["channel"],
            label=original.get("label", original["channel"]),
            min_duty=0,
            max_duty=100,
        )
        restore_channel(api, channel, original.get("setting"))
        print(f"Restored {channel.display_name}")
    report["applied"] = False
    report["restored_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write_report(report)
    print("Restored every pre-commissioning fan setting.")


def print_inventory(
    devices: list[dict[str, Any]], channels: list[Channel], skipped: list[str]
) -> None:
    board = board_details()
    print(f"Board: {board['vendor']} {board['name']} {board['version']}")
    print(f"Kernel hwmon: {', '.join(hwmon_devices()) or 'none'}")
    print("CoolerControl devices:")
    for device in devices:
        info = device.get("info") or {}
        driver = (info.get("driver_info") or {}).get("name") or "unknown"
        controllable = sum(
            1
            for value in (info.get("channels") or {}).values()
            if ((value or {}).get("speed_options") or {}).get("fixed_enabled")
        )
        print(f"  {device['type']:10} {device['name']} [{driver}] controls={controllable}")
    print(f"Safe automatic candidates: {len(channels)}")
    for channel in channels:
        print(f"  {channel.display_name}")
    for reason in skipped:
        print(f"  skipped: {reason}")


def commission(api: CoolerControlAPI, apply: bool) -> None:
    board = board_details()
    if board["vendor"] != EXPECTED_VENDOR or board["name"] != EXPECTED_BOARD:
        raise CommissionError(
            "Refusing fan writes on unexpected board "
            f"{board['vendor']!r} {board['name']!r}; expected "
            f"{EXPECTED_VENDOR!r} {EXPECTED_BOARD!r}"
        )
    devices = api.devices()
    statuses = api.statuses()
    channels, skipped = eligible_channels(devices, statuses)
    print_inventory(devices, channels, skipped)
    if not channels:
        raise CommissionError(
            "No safe motherboard fan channels are available. Confirm nct6775 is loaded and restart coolercontrold."
        )
    temperature = cpu_temperature(statuses)
    if temperature is None:
        raise CommissionError(
            "CoolerControl did not expose CPU temperature; refusing an unguarded sweep"
        )
    if temperature >= 75:
        raise CommissionError("CPU is already too warm for commissioning; let Helix idle first")

    snapshot = original_settings(api, channels, statuses)
    results = []
    completed = False
    report = {
        "board": board,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "applied": False,
        "completed": False,
        "results": results,
        "skipped": skipped,
        "original_settings": report_settings(channels, snapshot),
    }
    write_report(report)

    def interrupt(_signum: int, _frame: Any) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)
    print("Automatic sweep begins in five seconds; original control is restored on interruption.")
    time.sleep(5)
    try:
        for channel in channels:
            print(f"Testing {channel.display_name}...")
            try:
                try:
                    result = test_channel(api, channel)
                except ProtectedChannel as error:
                    skipped.append(str(error))
                    print(f"  protected: {error}")
                else:
                    results.append(result)
                    print(
                        f"  {result['high_rpm']} RPM at {result['high_duty']}%; "
                        f"safe floor {result['safe_floor']}%"
                    )
            finally:
                restore_channel(
                    api, channel, snapshot[(channel.device_uid, channel.name)]
                )
        if apply:
            if not results:
                raise CommissionError(
                    "Every candidate was protected; no fan settings were changed"
                )
            verified = {
                (result["device_uid"], result["channel"]) for result in results
            }
            apply_curves(
                api,
                devices,
                [
                    channel
                    for channel in channels
                    if (channel.device_uid, channel.name) in verified
                ],
                results,
            )
            print("Applied conservative CPU/GPU-max curves to verified fan channels.")
        completed = True
    finally:
        if not completed:
            for channel in channels:
                try:
                    restore_channel(
                        api, channel, snapshot[(channel.device_uid, channel.name)]
                    )
                except CommissionError as error:
                    print(f"RESTORE WARNING: {error}", file=sys.stderr)

    report["applied"] = apply
    report["completed"] = True
    write_report(report)
    print(f"Report: {STATE_PATH}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=("inventory", "commission", "restore"),
        nargs="?",
        default="inventory",
    )
    parser.add_argument(
        "--apply", action="store_true", help="retain generated conservative curves after a successful sweep"
    )
    parser.add_argument("--api-url", default=API_URL, help=argparse.SUPPRESS)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    password = os.environ.get("COOLERCONTROL_PASSWORD")
    api = CoolerControlAPI(args.api_url)
    try:
        try:
            api.login(password)
        except AuthenticationError:
            if password is not None or not sys.stdin.isatty():
                raise
            api.login(getpass.getpass("CoolerControl password: "))
        if args.command == "inventory":
            devices = api.devices()
            statuses = api.statuses()
            channels, skipped = eligible_channels(devices, statuses)
            print_inventory(devices, channels, skipped)
        elif args.command == "commission":
            commission(api, args.apply)
        else:
            restore_report(api)
        return 0
    except KeyboardInterrupt:
        print("Interrupted; original fan settings restored.", file=sys.stderr)
        return 130
    except CommissionError as error:
        print(f"helix-fan-commission: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
