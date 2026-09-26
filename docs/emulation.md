# NAS-first console emulation

Helix's generic emulation profile is deliberately **console-only**. Arcade/MAME
belongs to the separate `hamCade` project and must not be reimplemented here.

The console subsystem is controlled by:

```nix
helix.emulation.enable = true;
```

Setting it to `false` removes the console ROM automount, emulator launchers,
helper commands and preparation service from the next NixOS generation. It does
not delete NAS data or local emulator state.

## Ownership boundary

`nixos-helix` owns the Helix host integration for console emulation:

- the read-only `//192.168.1.8/roms` automount at `/mnt/infernalnexus/roms`;
- console launchers and packages;
- console saves, states, screenshots, metadata and emulator state below
  `/mnt/games_nvme/emulation`;
- bounded discovery of the mounted console library;
- optional metadata scraping for supported console systems.

`hamCade` exclusively owns arcade:

- MAME/libretro-MAME runtime policy;
- ES-DE arcade presentation;
- MAME DAT/XML interpretation and ROM auditing;
- arcade curation, playlists, artwork and descriptions;
- arcade saves, favourites, history and other application state.

The generic Helix emulation profile therefore exposes no standalone MAME
launcher, arcade DAT indexer, arcade audit command, arcade scraper target or
arcade state tree. The `helix.hamCade.enable` integration is separate.

Existing arcade-shaped directories left below `/mnt/games_nvme/emulation` by
older generations are not deleted automatically. They are historical mutable
state and require an explicit cleanup decision.

## Storage contract

The authoritative console ROM library is the dedicated
`//192.168.1.8/roms` share. It is automounted read-only at
`/mnt/infernalnexus/roms`.

Writable console state lives below `/mnt/games_nvme/emulation`. The
preparation helper resolves available PS2, PS3, PS4 and SNES directories from
the NAS into stable local symlinks while keeping the source collection
read-only.

## Public commands

The generic profile currently provides:

```text
helix-emulation-discover
helix-emulation-prepare
helix-emulation-scrape
helix-emulation-status
helix-pcsx2
helix-rpcs3
helix-shadps4
helix-retroarch
```

`helix-emulation-scrape` supports PS2 and SNES metadata generation. PS3 and
PS4 remain launcher-managed without an automated Skyscraper path.

Arcade is launched and maintained through the separate `hamcade` command.

## Activation

After changing the console profile, activate it through the normal Helix
workflow:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh test
# After runtime validation:
./scripts/rebuild.sh switch
```

A successful evaluation proves configuration consistency, not that every
physical controller, ROM or emulator behaves correctly. Keep live validation
separate from repository checks.
