# Codex mission: make Helix RetroArch-first

You are the implementation agent. OpenClaw is the live-machine discovery and
review agent. Read its discovery report before changing code.

## Inputs

Repository:
`/home/tristan/Projects/nixos-helix`

OpenClaw discovery report:
`/mnt/games_nvme/emulation/reports/openclaw-mame-discovery.md`

OpenClaw review report, when present:
`/mnt/games_nvme/emulation/reports/openclaw-retroarch-review.md`

The existing design documentation is in `docs/emulation.md` and
`docs/openclaw-emulation.md`.

## Goal

Make Helix's emulation profile a small, excellent RetroArch-first setup with a
clean deterministic arcade library. The authoritative ROM collection remains on
the Synology NAS and must stay read-only.

This is not a request for a broad emulator platform. Do not add frontends,
container stacks, databases, launchers, or speculative infrastructure.

## Required direction

- RetroArch is the primary and default emulation surface on Helix.
- Collapse the enabled emulation profile away from the current PCSX2/RPCS3/
  shadPS4/standalone-MAME/Skyscraper spread unless a piece is strictly required
  to produce or validate the RetroArch library.
- Initial arcade target is the actual MAME collection and DAT discovered by
  OpenClaw. Match the libretro core to that evidence; do not select a core by
  name alone or silently accept a ROM/core version mismatch.
- Generate the arcade playlist from the matching DAT rather than RetroArch's
  filename scanner.
- Keep the complete ROM set untouched. Curation is presentation metadata only.
- Exclude BIOS/device/mechanical/non-working/casino/software-list/test noise
  from the visible arcade playlist while preserving ROM dependencies.
- Use canonical game descriptions from the DAT.
- Keep mutable RetroArch state, playlists, thumbnails, saves, states,
  screenshots, remaps, overrides, logs, and generated reports below
  `/mnt/games_nvme/emulation`.
- Keep all source ROM/DAT paths under `/mnt/infernalnexus` read-only. Never
  rename, repair, rebuild, extract into, or write beside source ROMs.
- Preserve existing user RetroArch history, favourites, saves, states, remaps,
  and overrides. Generated files may be replaced only deterministically and
  with sensible backup/atomic-write behavior.
- Configure sensible Helix defaults based on the live OpenClaw report: Vulkan,
  PipeWire, Ozone, correct display behavior, and automatic DualSense handling.
  Do not hard-code event devices or Bluetooth addresses.
- Do not enable broad latency hacks. Rewind, run-ahead, frame delay, and similar
  changes stay off unless a tested per-game reason exists.

## Command surface

Prefer a very small public surface:

- `helix-retroarch`
- `helix-retroarch-refresh`
- `helix-retroarch-status`

The refresh command should regenerate/validate the deterministic library and
fail closed if the NAS mount, selected DAT, or expected core is wrong.

The status command must be quick and human-readable: mount state, detected DAT
and core, playlist count, missing content references, thumbnail coverage, and
controller visibility.

Remove obsolete public emulation commands and desktop entries when they no
longer fit the simplified design. Do not leave dead helpers documented as if
supported.

## Core/package discipline

Use packages available in the selected Nixpkgs release when they satisfy the
live ROM/DAT evidence. If an exact core pin is necessary, make the pin explicit,
small, reproducible, and documented. Do not pull in a second package universe
or unrelated dependencies.

Avoid expensive unrelated builds. In particular, do not introduce CUDA or
machine-learning build dependencies anywhere in this work.

## Verification

Before finishing:

1. Run formatting/static checks relevant to changed files.
2. Run the repository's emulation-focused tests.
3. Run the normal repository checks if practical without switching the live
   system.
4. Validate generated JSON/LPL syntax.
5. Prove every generated writable destination stays under
   `/mnt/games_nvme/emulation`.
6. Prove the NAS mount configuration remains read-only.
7. Do not run `nixos-rebuild switch` and do not use sudo.

If OpenClaw's evidence contradicts an assumption in the current repository,
change the repository to match the machine rather than preserving the
assumption.

Finish by summarizing exactly what changed, tests run, any remaining live-only
validation, and the one rebuild command Tristan should run.