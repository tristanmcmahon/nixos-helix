# Normal operation and recovery

Helix uses NixOS 26.05 from the root `nixos` channel. Repository checks and
rebuilds select the same Nixpkgs tree through `release-environment.sh` and fail
if it reports another NixOS release.

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

The current installation retains `system.stateVersion = "25.11"` because that
is when its persistent state was created. Do not raise it for an ordinary
channel update. The temporary 26.05 fresh-install entry is documented in the
reinstall guide.

## Recovery

Vim is available as both `vi` and `vim` on a text console. Plasma is the primary
desktop; Hyprland remains an optional SDDM session.

If a new generation cannot reach the desktop, select an older generation in
the systemd-boot menu. From a working generation, inspect the list and restore
the selected rollback as the default:

```bash
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
sudo nixos-rebuild switch --rollback
```

Automatic Nix garbage collection uses a 30-day age policy, so recent rollback
generations remain available without a repository-owned generation manager.
The generated hardware configuration contains no swap, so hibernation is not
supported unless swap is deliberately designed later.

For physical validation after `test`, follow
[hardware-validation.md](hardware-validation.md).
