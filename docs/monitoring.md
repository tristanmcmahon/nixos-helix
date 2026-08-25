# Monitoring and fan control

Helix keeps hardware telemetry locally and presents it as one restrained,
repository-owned dashboard. The suite is enabled by
`helix.monitoring.enable = true` in `configuration.nix` and can be removed as a
unit without disturbing the underlying hardware support.

## What runs

- Prometheus listens on `127.0.0.1:9090`, samples every 15 seconds, and retains
  400 days of history in its persistent state directory.
- node_exporter listens on `127.0.0.1:9100` and supplies CPU, memory,
  filesystem, network, disk-I/O, systemd, hwmon temperature, and fan data.
- nvidia_gpu_exporter listens on `127.0.0.1:9835` and reads the installed
  NVIDIA driver's `nvidia-smi` for RTX 5080 temperature, utilisation, VRAM,
  fan, clock, throttle, and power data.
- smartctl_exporter listens on `127.0.0.1:9633`, discovers local drives, and
  samples their SMART/NVMe health at a deliberately slower two-minute rate.
- Grafana listens on `127.0.0.1:3000` and provisions **Helix · Long View** from
  `config/monitoring/helix-overview.json`. Anonymous viewer access is safe only
  because the listener and every datasource are loopback-only.
- CoolerControl runs its daemon and GUI for sensor inspection and fan curves.

No monitoring port is opened in the firewall. None of the services sends
telemetry away from Helix, and Grafana's reporting and update checks are
disabled. Rebuilds and Nix garbage collection do not delete Prometheus history;
deleting its state directory is a separate, explicit operation.

Grafana's database-encryption key is generated once at first service start and
kept in its private state directory. The key is referenced through Grafana's
file provider, so it never enters the world-readable Nix store or this
repository.

## Using it

Launch **Helix Monitor** from Plasma or run:

```bash
helix-monitor
```

The dashboard defaults to the last 24 hours, refreshes every 15 seconds, and
offers useful ranges through one year. Prometheus and CoolerControl are linked
from the dashboard header. The same helper exposes the two operational views:

```bash
helix-monitor fans
helix-monitor status
```

The dashboard shows live CPU/GPU load, RAM/VRAM, thermal history, fan RPM,
local storage and network throughput, filesystem capacity, NVMe wear, storage
temperature, GPU board power, scrape health, and SMART status. A missing panel
usually means that the underlying device or driver does not expose that metric;
it is not replaced with guessed data.

## Commissioning fan control

CoolerControl is enabled, but the repository intentionally does not prescribe
curves on the first activation. Fan channel names, safe minimum duty cycles,
stop/start hysteresis, and which temperature should govern a channel are
physical facts that must be observed on Helix.

After `./scripts/rebuild.sh test`:

1. Open `helix-monitor fans` and record every detected fan, pump, and
   controllable channel.
2. Change one channel at a time for a few seconds and identify the physical fan.
   Do not lower a pump or an unidentified channel.
3. Establish the lowest stable RPM for each chassis fan before allowing a low
   duty value. Give start-up duty a margin above the stall point.
4. Use CPU package temperature for CPU cooling and a conservative blend of CPU
   and GPU temperature for shared case airflow. Apply hysteresis or smoothing
   so short Ryzen temperature spikes do not produce audible hunting.
5. Suspend and resume once, then confirm every controlled channel and RPM
   reading recover correctly.
6. Keep the firmware's existing cooling policy available as the rollback until
   the curves have survived a sustained CPU/GPU load test.

CoolerControl's discovered devices and profiles are mutable machine state. Once
the physical map is known, document the channel names and validated limits here;
do not commit raw inventory dumps or unstable device IDs merely to make the
configuration look complete.

## Validation and rollback

Validate without activation, then try one boot's runtime state before making it
persistent:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh test
helix-monitor status
```

Check all three Prometheus targets at `http://localhost:9090/targets`, inspect
**Helix · Long View**, and confirm CoolerControl sees the expected devices. Use
`./scripts/rebuild.sh switch` only after those checks. A previous NixOS
generation restores the prior service set; any CoolerControl profile should
also be disabled in its GUI before testing a conflicting firmware curve.
