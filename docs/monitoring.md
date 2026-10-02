# Monitoring and fan control

Helix's metrics history lives on the Netdata parent on Infernalnexus. Helix runs
a Netdata child that streams to it, plus live cooling control. Both are enabled
by `helix.monitoring.enable = true` in `configuration.nix` and can be removed as
a unit without disturbing the underlying hardware support.

## What runs

- Netdata, loopback-only on `127.0.0.1:19999`, collects host, process,
  filesystem, network, sensor, NVIDIA, SMART and systemd-unit metrics and
  streams them to the parent on Infernalnexus. Its own database is one hour of
  RAM; the parent keeps the persistent history. See
  [operations.md](operations.md#central-netdata) for the stream key.
- CoolerControl runs its daemon and GUI for sensor inspection and fan curves.

No monitoring port is opened in the firewall. The earlier local
Prometheus/Grafana stack was retired in favour of the Infernalnexus parent; an
invariant keeps it from returning. Its old history in `/var/lib/prometheus2`
and `/var/lib/grafana` is no longer used and can be deleted by hand.

## Using it

Launch **Helix Monitor** from Plasma or run:

```bash
helix-monitor           # the Netdata parent on Infernalnexus
helix-monitor fans      # CoolerControl
helix-monitor status    # coolercontrold and netdata
```

The parent dashboard shows both `infernalnexus` and `helix`. If the NAS is
offline, the child keeps collecting locally and resumes streaming when it
returns; Helix itself is unaffected.

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

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh test
helix-monitor status
```

Confirm `helix` appears on the parent dashboard and CoolerControl sees the
expected devices before `./scripts/rebuild.sh switch`. A previous NixOS
generation restores the prior service set. `helix-monitor restore` restores the
pre-commissioning CoolerControl settings as a separate mutable-state rollback.
