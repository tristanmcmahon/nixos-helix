# NAS-first emulation

The entire emulator subsystem is controlled by one option:

```nix
helix.emulation.enable = true;
```

Setting it to `false` removes the ROM automount, emulator packages, desktop
entries, helper commands, and preparation service from the next NixOS
generation. It does not delete any NAS data.

## Storage contract

The authoritative ROM library is the dedicated `//192.168.1.8/roms` share. The
module automounts it read-only at `/mnt/infernalnexus/roms` and never renames,
moves, or repairs files there. It recognizes PS2, PS3, PS4, SNES, and
`MAME 0.275 ROMs (merged, inc CHDs)` directories case-insensitively. When a
system directory contains a nested `roms` directory, that directory wins; this
matches the tfpga layout.

Writable data lives below `/mnt/infernalnexus/nas1/Emulation`:

- `state/`: isolated HOME and XDG trees for each emulator
- `saves/`, `states/`, and `screenshots/`: user data
- `bios/`: user-supplied firmware links or files
- `metadata/` and `tools/downloaded_media/`: scraped ES-DE metadata and artwork
- `tools/reports/`: discovery and DAT-audit reports

Only the `Helix NAS` desktop entries should be used. They force the emulator's
HOME, config, cache, and data directories onto the NAS before starting PCSX2,
RPCS3, shadPS4, MAME, or RetroArch with bsnes.

## First run and maintenance

After activating the configuration, inspect the setup:

```bash
helix-emulation-status
helix-emulation-discover
```

The graphical-session service runs preparation automatically. It creates the
writable tree, links recognized systems without changing their sources, and
indexes arcade DAT/XML files found anywhere in the ROM share up to four levels
deep.

Audit the MAME 0.275 collection against the best matching NAS DAT:

```bash
helix-emulation-audit-arcade
```

This is deliberately read-only. Igir writes a CSV report under
`Emulation/tools/reports`; it does not rebuild or mutate the set.

Fetch artwork and generate ES-DE metadata one platform at a time:

```bash
helix-emulation-scrape ps2
helix-emulation-scrape ps3
helix-emulation-scrape ps4
helix-emulation-scrape snes
helix-emulation-scrape arcade
```

Skyscraper uses ScreenScraper by default. An alternative supported scraper can
be supplied as the second argument. Its cache, downloaded media, and generated
metadata all remain on the NAS. Scraping service credentials, BIOS/firmware,
games, and console keys remain user-supplied and are not stored in this
repository.
