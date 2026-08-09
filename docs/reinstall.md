# Fresh reinstall

A fresh reinstall is a separate destructive project, not part of an ordinary
Helix rebuild. This repository contains no partitioning or formatting command.
Run `./scripts/reinstall-preflight.sh` on the current installation first; it is
read-only and never labels a disk safe to erase.

A wiped installation using the NixOS 26.05 installer installs only 26.05.
There is no intermediate 25.11 installation or upgrade step.

## Sequence

Follow this order without skipping a gate:

1. Run the canonical backup.
2. Manually inspect and verify its completed set.
3. Save and manually review `hardware-inventory.sh` output.
4. Record the current full `origin/main` commit.
5. Create and verify official NixOS 26.05 installation media.
6. Boot that media explicitly in UEFI mode.
7. In GParted, visually identify each device by model, serial, and capacity.
8. Manually create the layout below, checking the target before each change.
9. Clone the canonical repository and check out the approved commit.
10. Run the read-only `check-install-storage.sh` and inspect its evidence.
11. Mount only HELIX_ROOT at `/mnt` and HELIX_EFI at `/mnt/boot`.
12. Run `nixos-generate-config --root /mnt`.
13. Continue the configuration, continuity, install, and postflight workflow below.
14. Restore user data and secrets with the canonical restore script.

## Verified backup gate

The only supported reinstall backup command writes timestamped archive sets to
the existing Infernalnexus CIFS share at `/mnt/infernalnexus/nas1/backup`:

```bash
cd /home/tristan/Projects/nixos-helix
./scripts/backup-for-reinstall.sh
```

The script refuses an unmounted directory or any source other than
`//192.168.1.8/nas1`, archives Unix metadata inside tar files, inventories the
installation and repository, verifies checksums and archive readability, and
promotes an `.INCOMPLETE` directory only after all checks pass. It never follows
`/mnt/games_nvme`. Installed Steam games, workshop payloads, downloads and
shader caches are excluded; Steam userdata, compatdata and configuration remain.

After it finishes, manually inspect `BACKUP-README.txt` in the reported set,
then run these commands from that completed directory:

```bash
sha256sum --check SHA256SUMS
tar -tf home-tristan.tar >/dev/null
sudo tar -tf etc-nixos-secrets.tar >/dev/null
sudo tar -tf machine-identity.tar >/dev/null
```

Also inspect the repository patches and inventories, and extract representative
non-secret documents, dotfiles, Projects content, browser data and vault notes
into a temporary directory. Keep the backup until the fresh installation has
passed postflight. Seeing the backup directory alone is not proof of a complete
or manually reviewed backup.

## Official NixOS 26.05 media

Download the official NixOS 26.05 installer and its published checksum from
the official NixOS download infrastructure. Compare the locally calculated
`sha256sum` with the separately downloaded official checksum before writing
the image. Do not use an image whose checksum or signing source is uncertain.

## Manual GParted layout

Boot the verified installer in UEFI mode. In GParted, identify each physical
device visually by its model, serial, and capacity before every destructive
action. Kernel device names can change between boots and are not identities.

Create this layout manually:

- OS disk: GPT; a 10 GiB FAT32 EFI system partition labelled `HELIX_EFI`; an
  ext4 root labelled `HELIX_ROOT`; and exactly 240 GiB left unallocated at the
  end for a future Windows installation.
- Two separately identified Linux SSDs: one full-disk ext4 filesystem each,
  labelled `HELIX_SSD_A` and `HELIX_SSD_B`.
- Do not modify the existing ext4 GAMES_NVME filesystem with UUID
  `d07ac88e-34f6-4d56-9941-5ceaf52fd6bb`.

Close GParted, then run the repository's short read-only check:

```bash
./scripts/check-install-storage.sh
```

It verifies labels, types, the protected UUID, approximate ESP size, common OS
disk ancestry, and prints free-space evidence. It does not decide that a disk
is safe to erase and cannot prove the intended 240 GiB merely from a label;
Tristan must inspect the printed table and GParted layout.

Mount only HELIX_ROOT at `/mnt` and HELIX_EFI at `/mnt/boot` before generating
hardware configuration. Do not mount HELIX_SSD_A, HELIX_SSD_B, or GAMES_NVME
beneath `/mnt`; otherwise `nixos-generate-config` may introduce separately
managed data filesystems into `hardware-configuration.nix`.

## Temporary installation checkout

After manually preparing and mounting the target root at `/mnt` and its EFI
partition at the intended location, clone the exact approved commit into a
temporary checkout outside the target's canonical future checkout:

```bash
git clone https://github.com/tristanmcmahon/nixos-helix.git /tmp/nixos-helix-install
git -C /tmp/nixos-helix-install checkout APPROVED_COMMIT
sudo nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nixos-helix-install/hardware-configuration.nix
sudo install -d -m 0755 /mnt/var/lib/helix-install
sudo install -m 0444 /mnt/etc/nixos/hardware-configuration.nix \
  /mnt/var/lib/helix-install/hardware-configuration.nix
(cd /mnt/var/lib/helix-install && sudo sha256sum hardware-configuration.nix \
  | sudo tee hardware-configuration.nix.sha256)
git -C /tmp/nixos-helix-install rev-parse HEAD \
  | sudo tee /mnt/var/lib/helix-install/approved-commit
/tmp/nixos-helix-install/scripts/verify-hardware-continuity.sh \
  /tmp/nixos-helix-install/hardware-configuration.nix \
  /mnt/etc/nixos/hardware-configuration.nix \
  /mnt/var/lib/helix-install/hardware-configuration.nix
diff -u /tmp/helix-backup-inspection/hardware-configuration-repository.nix \
  /tmp/nixos-helix-install/hardware-configuration.nix || true
```

Preserve the newly generated file for later review. Repartitioning can change
filesystem UUIDs, so never blindly reuse the tracked hardware file and never
overwrite the canonical checkout merely to install. The normal configuration's
`system.stateVersion = "25.11"` remains the upgrade compatibility contract.
A wiped installation first created on NixOS 26.05 must additionally import
`fresh-install.nix`, which explicitly selects `system.stateVersion = "26.05"`.

Before `nixos-install`, verify `/mnt`, its EFI mount, all generated UUIDs, the
explicit target disk, and that no unrelated disk is below `/mnt`. The
repository-owned `fresh-install-configuration.nix` is the installer entry
point; it composes the maintained configuration with `fresh-install.nix` and is
not used by upgrades. From the temporary checkout using the 26.05 source, run:

```bash
export HELIX_NIXPKGS_PATH="$(nix-instantiate --find-file nixpkgs)"
./scripts/dev-shell.sh --run './scripts/check.sh'
nixos-rebuild dry-build \
  -I "nixpkgs=$HELIX_NIXPKGS_PATH" \
  -I "nixos-config=$PWD/fresh-install-configuration.nix"
sudo env HELIX_NIXPKGS_PATH="$HELIX_NIXPKGS_PATH" \
  NIX_PATH="nixpkgs=$HELIX_NIXPKGS_PATH" \
  nixos-install --root /mnt \
  -I "nixpkgs=$HELIX_NIXPKGS_PATH" \
  -I "nixos-config=$PWD/fresh-install-configuration.nix"
```

`release-environment.sh` validates and prints this explicit source, ignores an
ambient user `NIX_PATH`, and refuses a source whose release differs from
`release.nix`. The same tree therefore drives checks, the dry build, and install
without changing a channel.

The final command installs to the already reviewed and mounted `/mnt`; it does
not partition or format a disk. Recheck the mount topology immediately before
running it.

Also record how the authorized key and root-owned NAS credential will be
restored without storing either in Git or the Nix store.

## First boot and postflight

Clone the exact approved repository first. Preserve the newly generated hardware
configuration as the active machine definition; the old hardware, UUID, boot,
closure and generation inventories in the backup are reference evidence only.
Before any canonical rebuild, prove the generated hardware file still matches
the installer-preserved copy:

```bash
git clone https://github.com/tristanmcmahon/nixos-helix.git ~/Projects/nixos-helix
cd ~/Projects/nixos-helix
git checkout "$(cat /var/lib/helix-install/approved-commit)"
cp /var/lib/helix-install/hardware-configuration.nix hardware-configuration.nix
./scripts/verify-hardware-continuity.sh \
  /var/lib/helix-install/hardware-configuration.nix \
  /etc/nixos/hardware-configuration.nix hardware-configuration.nix
git switch -c hardware/helix-fresh-install
git add hardware-configuration.nix
git commit -m 'Record fresh Helix hardware configuration'
git push -u origin hardware/helix-fresh-install
```

Name the completed backup set explicitly and run the restore in its default,
read-only planning mode:

```bash
./scripts/restore-after-reinstall.sh helix-reinstall-YYYYMMDD-HHMMSS
```

Review the checksum, archive, collision, home-state and session results. Log out
of Plasma and all other graphical sessions for Tristan, switch to a text console,
then run the exact command printed by the plan:

```bash
./scripts/restore-after-reinstall.sh helix-reinstall-YYYYMMDD-HHMMSS --run
```

If the fresh home contains more than shell skeleton files and the canonical
checkout, the script refuses by default. Review every collision summary and use
`--merge-existing-home` only deliberately; it requires a second typed
confirmation and quarantines the existing home and secrets before replacement.
It never deletes files merely because they are absent from the backup.

The restore stages and revalidates all three logically separate archives, then
restores `/home/tristan`, `/etc/nixos/secrets`, the single
`towerofdoom.nmconnection` profile, and complete `/etc/ssh/ssh_host_*` key
pairs. No other `/etc` content is accepted. Run the restore locally before
relying on NetworkManager's restored profile or accepting SSH connections; it
checks restrictive profile metadata and compares restored public-key
fingerprints with the checksummed preinstall record. It does not activate old hardware
configuration, filesystem UUIDs, boot state, Nix stores, profiles, generations,
channels or inventories. After restoration, run:

```bash
./scripts/reinstall-postflight.sh
```

The checkout may be temporarily dirty after restoring its archived copy. Review
and retain the dedicated generated-hardware commit before treating the canonical
repository as complete. Postflight fails on any mismatch and checks configured
UUIDs; do not rebuild before it passes.

The restore handles the stacked systemd `autofs` trigger and real CIFS mount by
selecting exactly one CIFS layer for `//192.168.1.8/nas1`. Keep the NAS backup
and installer media until the complete hardware checklist passes.

## Finalise the temporary compatibility bridge

Only after the fresh installation has booted, restored data has been checked,
and postflight passes, prepare a separate reviewed cleanup change that:

1. replaces the tracked `hardware-configuration.nix` with the freshly generated file;
2. sets the canonical `stateVersion` to `26.05`;
3. removes `freshStateVersion` from `release.nix`;
4. removes `fresh-install.nix` and `fresh-install-configuration.nix`;
5. removes the fresh-install marker and dual-entry validation from `check.sh`.

Until that finalisation is merged, the 25.11 current-install state version and
26.05 fresh-install entry are one intentional temporary bridge. Do not perform
these removals before the new installation passes postflight.

## Recovery

If the new system does not boot, boot the verified installer ISO, mount the
installed root and EFI filesystems beneath `/mnt`, inspect logs under
`/mnt/var/log` and `journalctl --directory=/mnt/var/log/journal`, then use
`nixos-enter --root /mnt`. Re-run `nixos-install` against the existing mounted
target or reinstall systemd-boot only after rechecking the EFI mount. Restore
the preserved generated hardware configuration if UUIDs were recorded
incorrectly. Use `restore-after-reinstall.sh` against the same canonical archive
set for user and secret data; do not bypass its validation with direct extraction.
Do not delete the backup or installation media during recovery.
