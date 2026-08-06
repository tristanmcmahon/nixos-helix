# Canonical NAS reinstall backup record

Helix now has one reinstall backup workflow: run
`./scripts/backup-for-reinstall.sh` from the canonical checkout and write a new
timestamped set beneath `/mnt/infernalnexus/nas1/backup` on the
`//192.168.1.8/nas1` CIFS share.

The previous `HELIX_BACKUP_PATH`, `/mnt/VERIFIED-BACKUP`, generic physical or
network destination classification, `backup-source-lib.sh`, and
`create-backup-manifest.sh` mechanisms were removed. Production has no backup
destination argument or environment override.

The replacement stores home and root-owned secrets in separate tar archives so
Unix metadata survives CIFS storage. It records repository, hardware, storage,
boot, generation and package inventories; builds in an `.INCOMPLETE` directory;
verifies every checksum and both archives; checks representative dotfiles, SSH
and Projects paths; and creates `COMPLETE` only before atomic promotion.

The home audit measured about 12 GiB. `.cache`, desktop trash, incomplete
downloads, and Steam game/workshop/download/shader payloads are excluded.
Steam userdata, compatdata, app manifests and configuration remain included.
The separate games NVMe is never a backup target and is not traversed.

Validation includes shell syntax, ShellCheck, reinstall safety assertions,
obsolete-reference and tracked-archive checks, the complete repository check,
and review of the final diff. The real backup is deliberately not run during
repository validation.
