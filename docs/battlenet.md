# Battle.net and World of Warcraft (via Lutris)

Blizzard ships no native Linux client. `lutris` and `winetricks` are the only
Nix-managed pieces of this; Battle.net itself, its Wine prefix, World of
Warcraft's install, and your Blizzard account session are all mutable,
Lutris-managed state outside the Nix store, the same way Steam's and Heroic's
own state already is. Nothing here is downloaded, installed, or configured
during evaluation, build or activation — Lutris does all of it at runtime,
when you ask it to, matching the rest of this profile's conventions.

## Install Battle.net

1. Open **Lutris** (installed whenever `helix.gaming.enable` is true).
2. Search for **Battle.net** and choose the installer maintained by Lutris's
   community installers (the one with the most installs/highest rating is
   normally the current one; Blizzard changes its installer periodically, so
   prefer whichever one the Lutris team has most recently updated over an
   older cached entry).
3. Run the installer. On first use it downloads and sets up a Wine runner
   into `~/.local/share/lutris/runners/wine/` — this is the "current
   compatible Wine runner managed through Lutris" this profile is built
   around; Helix installs no system-wide Wine for you to pick instead.
4. The installer finishes by launching Battle.net's own setup/updater, which
   downloads Blizzard's launcher into the Wine prefix Lutris created. This
   step needs network access and may take a while; it is normal for it to
   look idle for a stretch while Battle.net's own updater runs.

By default Lutris keeps everything under `~/.local/share/lutris` and
`~/Games`. If you want the install on one of the existing data SSDs
(`/mnt/helix_ssd_a`, `_b`, `_c`) or `/mnt/games_nvme` instead of the home
directory, set that in Lutris's own preferences (or point the installer's
destination there directly) before installing — Helix does not default this
for you, and does not mount or provision storage specifically for Battle.net;
use whichever of the existing mounts has room, the same as you would for a
Heroic install.

## Launching, authenticating, and World of Warcraft

Launch Battle.net from Lutris (or the desktop entry Lutris creates) and sign
in with your Blizzard account as normal; this is Blizzard's own login flow
running inside the Wine prefix, not anything Helix mediates. Battle.net
should reopen correctly after a restart — Lutris keeps the prefix and its
saved session between launches, the same as any other Lutris game.

Once signed in, install World of Warcraft through Battle.net's own interface
exactly as you would on Windows: locate it in the app list, choose an install
location (inside the same Wine prefix's drive mapping), and let it download.
WoW's own patcher handles updates after that; there is nothing Helix-specific
to keep current beyond Lutris and winetricks themselves, which update with
the rest of the system on a normal NixOS rebuild.

## Troubleshooting

- **Battle.net or WoW can't find a DLL, or winetricks reports a missing
  dependency.** Run the relevant `winetricks` verb against the Battle.net
  prefix from Lutris's own game configuration (right-click the game → Configure
  → Runner options has a "Run winetricks" action, which correctly targets that
  game's prefix and runner). Only reach for a system-level fix if a Lutris- or
  Wine-side one doesn't resolve it.
- **Lutris itself is missing a library its Wine runner expects** (rare, but
  possible given NixOS's non-standard filesystem layout): override the
  package in a local change to `profiles/gaming.nix`, for example
  `pkgs.lutris.override { extraLibraries = pkgs: [ pkgs.someLibrary ]; }`.
  Add only what a specific, demonstrated error names — this profile
  deliberately does not pre-add libraries on spec.
- **Graphics, sound, mouse or keyboard don't work correctly in-game.** This
  profile changes nothing about `hardware/nvidia.nix`, PipeWire, or controller
  policy to get Battle.net working; if something regresses, it is more likely
  a Lutris/Wine runner setting (Lutris exposes DXVK/VKD3D, Vulkan ICD and
  Gamescope options per game under Configure → System options) than a Helix
  configuration issue. Compare against Steam/Heroic titles on the same
  hardware before assuming it is new.
- **Performance.** `helix-benchmark gpu` (`docs/benchmarking.md`) gives a
  baseline GPU number independent of any game, useful for telling a Lutris/Wine
  problem apart from a general system one.
- **A game hangs with no further draw calls, but the process and GPU stay
  alive.** Check `journalctl -k | grep Xid` for an NVIDIA Xid 109 — this is a
  known, unresolved, cross-title GPU/driver issue on this hardware, not
  specific to Battle.net or any single game. See `docs/roadmap.md`'s
  "Decisions needed" for the full case file before assuming a new,
  WoW-specific cause.

## Rollback

- **Remove Battle.net/WoW but keep the gaming profile**: delete the game and
  its prefix from inside Lutris (right-click → Remove, with the option to
  delete files), or remove `~/.local/share/lutris` entries and the install
  directory by hand. This never touches anything Nix-managed.
- **Remove Lutris and winetricks entirely**: revert the three lines this
  guide's changes added to `profiles/gaming.nix` (or set
  `helix.gaming.enable = false` to remove the whole gaming profile, Steam
  included) and rebuild. `tests/features-disabled.nix` asserts both packages
  disappear when gaming is disabled.
- **Roll back a whole generation**: `sudo nixos-rebuild switch --rollback`,
  same as any other Helix change; Lutris's own state under `~/.local/share`
  and your game installs are untouched either way, since none of it lives in
  the Nix store.
