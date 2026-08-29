# OpenClaw mission: Helix MAME in RetroArch

This is a machine-specific curation job. The result must fit Helix, not a
generic RetroArch installation.

## Non-negotiable boundaries

- Treat everything below `/mnt/infernalnexus` as read-only. Do not rename,
  delete, repair, extract, copy into, or create files on either NAS share.
- Put every report, playlist, thumbnail, cache, save, state, screenshot, and
  generated file below `/mnt/games_nvme/emulation`.
- Make persistent software and launcher changes in
  `/home/tristan/Projects/nixos-helix`; do not modify `/etc/nixos` directly.
- Do not request elevated execution. Ask Tristan to run the final
  `./scripts/rebuild.sh switch` after repository checks pass.
- Keep the OpenClaw gateway loopback-only. Do not weaken its systemd sandbox,
  NAS read-only path, approval policy, or secret exclusions.

## Discovery phase

Collect evidence first and save a concise report at
`/mnt/games_nvme/emulation/reports/openclaw-mame-discovery.md`.

1. Verify with `findmnt` that `/mnt/infernalnexus/roms` is the expected CIFS
   share and is mounted `ro`.
2. Locate the arcade ROM directory and bound every filesystem walk by a small
   maximum depth. Record archive count, CHD count, directory layout, and enough
   filenames to establish whether the set is merged, split, or non-merged.
   Do not hash the whole collection during discovery.
3. Locate the supplied arcade DAT/XML files. Read their headers and metadata;
   identify exact MAME version, set type, naming convention, and whether a
   software-list DAT has been mixed into the arcade set.
4. Inspect the Nixpkgs MAME executable and available libretro MAME cores. Do not
   assume that "current" matches the ROM set. Record exact versions and core
   paths, then select or pin the core that matches the authoritative DAT.
5. Inspect Helix's active Plasma/Wayland display geometry and refresh rate,
   NVIDIA/Vulkan renderer, PipeWire audio, and currently visible gamepads.
   Helix has an RTX 5080 and upstream `hid_playstation` support for DualSense,
   but live evidence wins over this note.
6. Inspect the current RetroArch state below
   `/mnt/games_nvme/emulation/state/retroarch` without discarding user-created
   favorites, history, saves, states, remaps, or overrides.

Stop and ask Tristan one focused question only if the evidence leaves a choice
that materially changes the library, such as whether working regional clones
should appear alongside parents. Otherwise proceed.

## Required finished state

- RetroArch is Nix-managed and launched only by `helix-retroarch` or its
  `RetroArch (Helix)` desktop entry.
- The selected libretro MAME core matches the supplied ROM/DAT set. Online core
  updates cannot silently replace the Nix-managed core.
- RetroArch uses Vulkan on the RTX 5080, PipeWire audio, the Ozone desktop UI,
  fullscreen behavior appropriate to the detected Helix display, and
  automatic controller profiles. Do not hard-code an event node or Bluetooth
  address.
- MAME defaults favor correct timing and predictable input. Keep rewind,
  run-ahead, frame delay, and broad latency hacks disabled unless a tested
  per-game override justifies one.
- Generate a deterministic `MAME.lpl` from the matching DAT, not RetroArch's
  filename scanner. Use canonical descriptions and stable paths into the
  read-only ROM share.
- The main playlist contains playable arcade games, not BIOS sets, devices,
  samples, mechanical machines, non-working entries, utilities, fruit/casino
  machines, or computer/software-list noise. Preserve any ROM dependencies
  required by the collection's merged/split layout.
- Keep the complete ROM set untouched on the NAS. Curation is presentation
  metadata only; exclusions belong in a reproducible filter or generated
  playlist on the SSD.
- Put box/title/snap artwork in RetroArch's expected thumbnail hierarchy on the
  SSD. Reuse suitable NAS artwork if present; otherwise add a separate,
  explicit user-run fetch helper because OpenClaw itself has no general network
  access.
- Use platform-specific save, state, screenshot, playlist, thumbnail, remap,
  override, log, and cache directories below the SSD root. Preserve atomic
  writes and back up an existing generated file before replacing it.
- Add a `helix-retroarch-mame-refresh` command that regenerates and validates
  the playlist from the selected DAT without modifying ROMs. It must fail
  closed if the NAS mount, DAT version, or expected core is wrong.
- Add a fast `helix-retroarch-mame-status` command that reports mount state,
  DAT/core versions, playlist entry count, missing ROM references, thumbnail
  coverage, and controller visibility.

## Validation and handoff

Run the repository's normal checks. Also validate every generated JSON/playlist
file, prove that all playlist content paths exist, prove that every writable
path resolves below `/mnt/games_nvme/emulation`, and prove the ROM mount remains
read-only. Launch one representative game only after Tristan approves the
title; report exact command output if the core rejects it.

Finish with a short report covering the detected set, chosen core, number of
visible games, exclusions, artwork coverage, controller mapping, validation
results, changed repository files, and the single rebuild command Tristan must
run.
