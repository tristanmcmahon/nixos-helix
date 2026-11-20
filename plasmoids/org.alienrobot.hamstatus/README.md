# alienrobot Service Health

A deliberately small Plasma 6 panel plasmoid for Helix.

It consumes the existing read-only hamFence health feed at
`https://home.alienrobot.org/api/services`. The widget does not probe services,
run a daemon, keep history, or talk to application APIs. hamFence remains the
health authority.

## Panel model

Four aggregate pips:

- **ARR** — Sonarr, Radarr, Whisparr, Prowlarr
- **MEDIA** — Plex, Seerr, Mylar, LazyLibrarian
- **GET** — SABnzbd, Deluge
- **SYS** — Netdata, Pi-hole, DSM

Green means every service in the group is reachable, amber means partial
degradation, red means every known service in the group is down, and grey means
the hamFence feed itself is unavailable or the group state is unknown.

Click a panel pip to open that group. Click an individual service row to open its
existing private web interface.

## Scaling

The settings page exposes independent horizontal and vertical scale percentages
(50–200%). The compact representation also changes from a row to a column when
placed on a vertical Plasma panel.

## Cost

The default is one small cached JSON GET every 10 seconds. A three-second local
watchdog aborts a stalled request. There are no per-service requests, effects,
charts, background processes, or continuously running animations.

## Isolated development install

This directory is intentionally self-contained so it can be developed while the
rest of nixos-helix is being refactored.

```bash
cd ~/Projects/nixos-helix/plasmoids/org.alienrobot.hamstatus
./install.sh validate
./install.sh install
```

Then enter Plasma panel Edit Mode and add **alienrobot Service Health**.

This first pass is user-local only. NixOS packaging/integration should be added
after the concurrent Helix refactor settles, keeping this package unchanged.
