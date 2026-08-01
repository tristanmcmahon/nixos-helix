# Installation and recovery

This repository is for the real Helix workstation. Its generated
`hardware-configuration.nix` contains Helix's filesystem UUIDs, initrd modules,
platform, and AMD microcode setting. Preserve it exactly. A different machine
must generate its own hardware module during installation; never copy Helix's
identifiers or run `nixos-generate-config` over this checkout.

## Fixed installation compatibility

`system.stateVersion = "25.11"` records the original installation's persistent
state compatibility. Channel upgrades do not change it.

Helix boots in UEFI mode with systemd-boot. The maintained boot module keeps EFI
variable access enabled and a five-second menu timeout. Storage layout and
boot-critical drivers remain in the generated hardware module.

The RTX 5080 uses NVIDIA's open kernel modules with the matching proprietary
user-space driver. NixOS 25.11 has no `hardware.nvidia.branch` option, so
Nixpkgs selects the stable driver without a package override.

## First use

Treat this checkout as the only maintained source. `/etc/nixos` may remain as
the installer-created fallback, but routine commands must select this checkout
explicitly:

```bash
cd ~/Projects/nixos-helix
./scripts/check.sh
./scripts/rebuild.sh test
```

Before `test`, confirm the expected account, New Zealand locale, systemd-boot
settings, and generated filesystem definitions. Set account passwords locally;
passwords and hashes do not belong in this repository or the Nix store.

After the checks in [hardware-validation.md](hardware-validation.md) pass, make
the generation persistent with:

```bash
./scripts/rebuild.sh switch
```

## Traditional channel workflow

This configuration follows the root `nixos` channel. Inspect it before an
update and read the target release notes:

```bash
sudo nix-channel --list
sudo nix-channel --update nixos
sudo nixos-rebuild build --upgrade \
  -I "nixos-config=$PWD/configuration.nix"
```

Do not combine a release upgrade with unrelated hardware changes, and never
bump `system.stateVersion` merely because the channel changed.

## Recovery

List generations with:

```bash
sudo nix-env --profile /nix/var/nix/profiles/system --list-generations
```

If the current generation cannot reach Plasma, select an older generation in
the systemd-boot menu. Once booted into it, make it the default again:

```bash
sudo nixos-rebuild switch --rollback
```

The nightly cleanup keeps the active system generation plus the two newest
other generations. It does not delete user profile generations or channels. A
missed 02:00 run executes after the next boot, and unreachable store paths are
collected only after obsolete system-generation links are removed.
