# Helix health and lifecycle

`helix-health` is a read-only, one-screen report covering NixOS/kernel and the
current generation, NVIDIA status, RAM/zram/swap, local disk space, failed system
and user units, OpenClaw gateway/version, monitoring services, and the selected
root NixOS channel and its age where available. Missing optional session data is
shown as a warning rather than aborting the report.

`helix-update` is the deliberate attended update path. It only operates on
`/home/tristan/Projects/nixos-helix`, refuses any dirty or untracked work tree,
updates the root channel, runs `scripts/check.sh`, builds a candidate, displays
`nvd diff`, test-activates, then switches. It uses `nom` when present and retains
raw build output during bootstrap. It does not schedule updates or run GC.

Helix uses native persistent weekly Nix GC with the existing one-hour randomized
delay and deletes generations older than 14 days. Store optimisation stays
weekly. The 32 GiB workstation uses zstd zram at 50% RAM and priority 100; no
disk swap is created. systemd-oomd watches root and user slices, not system.slice.

OpenClaw comes from `openclaw/nix-openclaw` revision
`d3760a6f103642f11e24bc01ee9aec80a0153774`, fetched with a fixed unpacked hash.
Its first-party `nix/packages` definition pins stable OpenClaw 2026.7.1-2. The
configuration asserts a minimum of 2026.6.9, and retains Nix mode, loopback-only
network access, Ollama, secret-file handling, and the existing systemd sandbox.
