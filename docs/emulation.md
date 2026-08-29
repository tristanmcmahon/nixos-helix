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
moves, repairs, extracts into, or writes files there.

Writable emulation state lives below `/mnt/games_nvme/emulation`. ROMs and DATs
on the NAS are source material; playlists, thumbnails, saves, states, reports,
configuration, and other generated data belong on the local games NVMe.

## Codex + OpenClaw workflow

OpenClaw and Codex have deliberately different jobs:

- **OpenClaw** inspects the real Helix machine, mounted ROM collection, supplied
  DATs, display/audio stack, controllers, and current RetroArch state. Its
  service sandbox makes `/mnt/infernalnexus` read-only while allowing reports
  below `/mnt/games_nvme/emulation`.
- **Codex** edits the `nixos-helix` repository using the evidence OpenClaw
  collected. It is responsible for the declarative RetroArch implementation
  and tests, not for guessing the live ROM layout.
- OpenClaw then reviews Codex's diff against the live evidence; Codex gets one
  focused final pass to fix concrete review findings.

Run the coordinated pass from a clean checkout on Helix:

```bash
cd /home/tristan/Projects/nixos-helix
bash scripts/helix-emulation-ai.sh
```

The coordinator does **not** rebuild/switch NixOS and does not run a full
emulation closure build. Its final gates are syntax/evaluation checks only, so
it cannot accidentally turn a RetroArch task into a large unrelated build.

After reviewing the resulting diff, activate it normally:

```bash
./scripts/rebuild.sh switch
```

Then use the status command produced by the completed RetroArch implementation
to perform live post-switch validation.

## Agent missions

`docs/openclaw-emulation.md` is the live discovery specification.

`docs/codex-emulation.md` is the implementation specification. It explicitly
requires a small RetroArch-first surface and tells Codex to remove the current
multi-emulator spread where it is no longer needed.

`docs/openclaw-retroarch-review.md` is the read-only engineering review gate.
OpenClaw writes review findings to the emulation SSD rather than modifying the
repository during that turn.

All three missions preserve the same hard rule: the NAS is authoritative and
read-only; curation changes presentation metadata and local state, never the
ROM archive.

## Current profile

Until the Codex + OpenClaw pass is run and its resulting change is activated,
`profiles/emulation.nix` still describes the previous broader emulator stack.
Do not treat that transitional implementation as the desired end state. The
new target is a clean RetroArch-first Helix setup, beginning with a deterministic
DAT-driven arcade library.