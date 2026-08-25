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

## Automatic fan commissioning

Helix's ASUS TUF GAMING X570-PLUS (WI-FI) exposes its Nuvoton controller through
the kernel's supported `nct6775` WMBD path. The driver provides CoolerControl
with motherboard fan RPM and PWM channels without a forced chip identifier.

Commissioning is automated:

```bash
helix-monitor inventory
helix-monitor commission
```

The commissioner works only on the exact Helix board and only on spinning,
fixed-speed-capable Nuvoton channels. NVIDIA channels, named pump/AIO/water
channels, stopped headers, and pump-like high-RPM channels are excluded. It
probes upward first, protects any newly detected high-speed channel before a
downward step, never tests below 40% duty, watches CPU temperature, and recovers
a stalled fan at full duty. Every original control mode is restored after its
test or on interruption. After every safe fan passes, it applies a conservative
maximum-of-CPU-and-GPU curve with a measured safety margin.

No pump is fitted to Helix. The high-speed auxiliary guard remains to avoid
mistaking the X570 chipset fan for an ordinary case or CPU fan. Commissioning
stores the complete previous control state before its first write. Restore it
without opening the GUI:

```bash
helix-monitor restore
```

The report is retained at
`~/.local/state/helix/fan-commissioning.json`. CoolerControl profiles remain
mutable machine state, while the board driver and guarded commissioning policy
are repository-owned.

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
generation restores the prior service set. `helix-monitor restore` restores the
pre-commissioning CoolerControl settings as a separate mutable-state rollback.
