# Normal operation and recovery

Helix uses the NixOS 26.05 release pinned in `nixpkgs.json`. Repository checks,
rebuilds, CI and `helix-update` select that tree through
`release-environment.sh` and fail if it reports another NixOS release;
`nix.nixPath` exposes the same tree to ad-hoc Nix commands. The root channel is
no longer used. On a fresh install, set `HELIX_NIXPKGS_PATH` to the installer's
tree for the first build if the pin cannot be fetched yet.

The tracked `hardware-configuration.nix` belongs to the currently installed
machine. Do not run `nixos-generate-config` over this checkout. Fresh
installation and hardware replacement are covered separately in
[reinstall.md](reinstall.md).

## Build and activate

From the canonical checkout:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh test
# After runtime validation:
./scripts/rebuild.sh switch
```

`dry-build` and the repository check do not activate the result. `test` changes
the running system until reboot. `switch` makes it the selected boot generation.
The `dry-activate` action is available when an activation diff is useful.

The current installation was created on NixOS 26.05, so
`system.stateVersion = "26.05"` is its permanent compatibility floor. Do not
raise it for an ordinary Nixpkgs update.

## Recovery

Vim is available as both `vi` and `vim` on a text console. Plasma is the only
desktop session.

If a new generation cannot reach the desktop, select an older generation in
the systemd-boot menu. From a working generation, inspect the list and restore
the selected rollback as the default:

```bash
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
sudo nixos-rebuild switch --rollback
```

Automatic Nix garbage collection deletes ordinary generations older than 14
days. The attended `helix-update` transaction additionally pins its verified
previous generation at `/nix/var/nix/gcroots/helix-known-good` so at least one
recently qualified fallback remains in the store independent of that age limit.
This is a protected store closure, not an autonomous boot watchdog. On boot
failure select the prior generation from systemd-boot, then inspect state
before manually promoting anything else.
The generated hardware configuration contains no swap, so hibernation is not
supported unless swap is deliberately designed later.

For physical validation after `test`, follow
[hardware-validation.md](hardware-validation.md).
