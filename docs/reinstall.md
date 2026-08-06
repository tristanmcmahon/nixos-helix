# Fresh reinstall qualification

A fresh reinstall is a separate destructive project, not part of an ordinary
Helix rebuild or release migration. This guide deliberately provides no
unattended erase command. Run `./scripts/reinstall-preflight.sh` on the current
installation first; it is read-only and never labels a disk safe to erase.

A wiped installation using the NixOS 26.05 installer installs only 26.05.
There is no intermediate 25.11 installation or upgrade step.

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
./scripts/reinstall-postflight.sh
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
