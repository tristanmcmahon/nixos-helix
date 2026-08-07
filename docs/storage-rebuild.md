# Guarded fresh-storage rebuild

The repository separates evidence collection, target approval, OS erasure, SSD
reclamation, and mounting. No script guesses a kernel device name. Destructive
tools accept only stable whole-disk `/dev/disk/by-id/...` identities plus exact
model, serial, size bounds, role, approved Git commit, and completed backup set
recorded in the ignored local manifest.

## Layout

The OS GPT contains a 10 GiB EFI system partition (`HELIX_EFI`, FAT32), then an
ext4 root (`HELIX_ROOT`) ending exactly 240 GiB before the GPT usable end. That
last 240 GiB stays unallocated: it is not formatted as NTFS. Each separately
approved SSD receives one full-disk ext4 partition, labelled `HELIX_SSD_A` or
`HELIX_SSD_B`. NixOS mounts those at `/mnt/helix_ssd_a` and
`/mnt/helix_ssd_b`. The existing GAMES_NVME UUID
`d07ac88e-34f6-4d56-9941-5ceaf52fd6bb` is a protected invariant and is never a
target.

## Approval and operation

On the installed system, first run the read-only inventory and save its mode
0600 report:

```bash
./scripts/storage-inventory.sh helix-storage-inventory.txt
./scripts/create-storage-target-manifest.sh helix-storage-inventory.txt
```

Fill every blank in `storage/reinstall-targets.local.conf` from inspected
evidence. A blank or guessed value is not actionable. Record a full approved
commit and exact completed backup-set basename. Re-run inventory on verified
NixOS 26.05 media and compare every identity before using `--plan`.

The OS and SSD scripts are separate and default to refusal. Plan mode performs
all identity, topology, repository, and backup archive/checksum validation but
changes no disk. Run mode additionally requires root, an interactive terminal,
UEFI installation media or explicit recovery marker, and exact disk-specific
typed confirmations. It refuses mounted targets, active swap/holders, removable
targets, the installer device, a block-backed NAS topology, and any disk holding
GAMES_NVME. It never uses `blkdiscard` or block-device wildcards.

After formatting, `mount-fresh-storage.sh` only mounts unique verified labels
beneath `/mnt`; it does not format or partition and deliberately leaves
GAMES_NVME outside the generated installation topology.

## Future Windows installation

Windows is not installed here. Later, direct Windows 11 only to the unallocated
240 GiB and allow it to create its own NTFS, MSR, and recovery partitions. Do
not delete or format HELIX_EFI or HELIX_ROOT. Windows may change firmware boot
order. Battlefield 6 requires TPM 2.0 and Secure Boot, but signed Helix boot is
outside this work; do not enable Secure Boot until that path has a separate
review.
