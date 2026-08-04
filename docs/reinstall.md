# Fresh reinstall qualification

A fresh reinstall is a separate destructive project, not part of an ordinary
Helix rebuild or release migration. This guide deliberately provides no
unattended erase command. Run `./scripts/reinstall-preflight.sh` on the current
installation first; it is read-only and never labels a disk safe to erase.

A wiped installation using the NixOS 26.05 installer installs only 26.05.
There is no intermediate 25.11 installation or upgrade step.

## Verified backup gate

Use a destination on a physically separate device from the intended target.
Record its device path, filesystem UUID, mount point, date, and available space.
Back up at least `/home/tristan`, `Projects`, `.ssh`, `/etc/nixos/secrets`, the
current `hardware-configuration.nix`, the repository commit and uncommitted
patch, browser data that is not independently synchronised, Obsidian vaults,
and all other non-reproducible data. 1Password application state is not a
substitute for separately retained account recovery information.

One suitable file-preserving pattern, after replacing the explicit destination,
is:

```bash
sudo rsync -aHAX --numeric-ids --info=progress2 /home/tristan/ /mnt/VERIFIED-BACKUP/home-tristan/
sudo rsync -aHAX --numeric-ids /etc/nixos/secrets/ /mnt/VERIFIED-BACKUP/etc-nixos-secrets/
git -C ~/Projects/nixos-helix rev-parse HEAD > /mnt/VERIFIED-BACKUP/nixos-helix-commit.txt
git -C ~/Projects/nixos-helix diff --binary > /mnt/VERIFIED-BACKUP/nixos-helix-working-tree.patch
findmnt -n -o SOURCE,FSTYPE,UUID -T /mnt/VERIFIED-BACKUP \
  | sudo tee /mnt/VERIFIED-BACKUP/BACKUP-SOURCE.txt
sudo ./scripts/create-backup-manifest.sh /mnt/VERIFIED-BACKUP
sudo find /mnt/VERIFIED-BACKUP -maxdepth 3 -printf '%M %u:%g %s %p\n' | less
(cd /mnt/VERIFIED-BACKUP && sudo sha256sum --check SHA256SUMS)
```

Open representative documents, photographs, SSH public data, vault notes, and
repository files directly from the backup. Confirm with `lsblk -f` and
`findmnt` that the backup is not stored on the disk that may be erased. The
manifest helper enumerates with NUL delimiters, builds outside the backup tree,
explicitly excludes any old manifest, verifies every readable file, and then
installs the replacement atomically. A separate partition on the target disk
is not a physically separate backup.

## Official NixOS 26.05 media

Download the official NixOS 26.05 installer and its published checksum from
the official NixOS download infrastructure. Compare the locally calculated
`sha256sum` with the separately downloaded official checksum before writing
the image. Do not use an image whose checksum or signing source is uncertain.

## Live-environment discovery and destructive gate

Boot the verified installer, establish networking, then run `lsblk -f`,
`findmnt`, `blkid`, and `bootctl status`. Record the exact full target device
path and identify the EFI system partition and intended root filesystem. No
other disk may be mounted below `/mnt`.

Stop before partitioning or formatting. After inspecting the live machine,
Tristan must manually type a phrase containing the resolved full device path:

```text
ERASE /dev/nvme0n1 AND INSTALL HELIX 26.05
```

The example is not a declaration that `/dev/nvme0n1` is the target. Generate
machine-specific commands only in the live environment. Every destructive
command must name one verified full device path; never use a wildcard.

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
diff -u ~/BACKUP/hardware-configuration.nix /tmp/nixos-helix-install/hardware-configuration.nix || true
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

Restore runtime data with the intended ownership and mode, then clone the exact
commit recorded in `/var/lib/helix-install/approved-commit`. Before any canonical
rebuild, copy the preserved generated hardware file into the checkout and prove
it still matches `/etc/nixos`:

```bash
git clone https://github.com/tristanmcmahon/nixos-helix.git ~/Projects/nixos-helix
cd ~/Projects/nixos-helix
git checkout "$(cat /var/lib/helix-install/approved-commit)"
cp /var/lib/helix-install/hardware-configuration.nix hardware-configuration.nix
./scripts/verify-hardware-continuity.sh \
  /var/lib/helix-install/hardware-configuration.nix \
  /etc/nixos/hardware-configuration.nix hardware-configuration.nix
HELIX_BACKUP_PATH=/mnt/VERIFIED-BACKUP ./scripts/reinstall-postflight.sh
git switch -c hardware/helix-fresh-install
git add hardware-configuration.nix
git commit -m 'Record fresh Helix hardware configuration'
git push -u origin hardware/helix-fresh-install
```

The checkout is expected to be temporarily dirty after copying the generated
hardware file. Push and review that dedicated hardware commit before treating
the canonical repository as complete. Postflight fails on any mismatch and
checks that every configured UUID exists; do not rebuild before it passes.

The automount must be active and waiting before access. Trigger the NAS only
after the static checks, and keep the verified backup and installer media until
the complete hardware checklist passes.

## Recovery

If the new system does not boot, boot the verified installer ISO, mount the
installed root and EFI filesystems beneath `/mnt`, inspect logs under
`/mnt/var/log` and `journalctl --directory=/mnt/var/log/journal`, then use
`nixos-enter --root /mnt`. Re-run `nixos-install` against the existing mounted
target or reinstall systemd-boot only after rechecking the EFI mount. Restore
the preserved generated hardware configuration if UUIDs were recorded
incorrectly. Restore user and secret data only from the independently verified
backup; do not delete the backup or installation media during recovery.
