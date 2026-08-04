# Fresh reinstall qualification

A fresh reinstall is a separate destructive project, not part of an ordinary
Helix rebuild or release migration. This guide deliberately provides no
unattended erase command. Run `./scripts/reinstall-preflight.sh` on the current
installation first; it is read-only and never labels a disk safe to erase.

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
sudo find /mnt/VERIFIED-BACKUP -type f -print0 | sudo sort -z | sudo xargs -0 sha256sum \
  > /mnt/VERIFIED-BACKUP/SHA256SUMS
sudo find /mnt/VERIFIED-BACKUP -maxdepth 3 -printf '%M %u:%g %s %p\n' | less
sudo sha256sum --check /mnt/VERIFIED-BACKUP/SHA256SUMS
```

Open representative documents, photographs, SSH public data, vault notes, and
repository files directly from the backup. Confirm with `lsblk -f` and
`findmnt` that the backup is not stored on the disk that may be erased.

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
diff -u ~/BACKUP/hardware-configuration.nix /tmp/nixos-helix-install/hardware-configuration.nix || true
```

Preserve the newly generated file for later review. Repartitioning can change
filesystem UUIDs, so never blindly reuse the tracked hardware file and never
overwrite the canonical checkout merely to install. Keep the deliberate
`system.stateVersion = "25.11"` compatibility contract unless a separate new-
installation policy is explicitly approved.

Before `nixos-install`, verify `/mnt`, its EFI mount, all generated UUIDs, the
explicit target disk, and that no unrelated disk is below `/mnt`. Then, from the
temporary checkout using the 26.05 source, run:

```bash
./scripts/check.sh
nixos-rebuild dry-build -I "nixos-config=$PWD/configuration.nix"
```

Also record how the authorized key and root-owned NAS credential will be
restored without storing either in Git or the Nix store.

## First boot and postflight

Restore runtime data with the intended ownership and mode, clone the approved
repository to `~/Projects/nixos-helix`, and record the installed commit. Run:

```bash
cd ~/Projects/nixos-helix
./scripts/reinstall-postflight.sh
```

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
