# Routine backups

`services/backup.nix` takes a nightly restic snapshot of the state a rebuild
cannot recreate:

- `/home/tristan`, except caches, Trash, the Steam library and build outputs;
- `/etc/nixos/secrets`;
- `/etc/ssh` (host keys);
- `/etc/NetworkManager/system-connections`.

Snapshots go to `/mnt/infernalnexus/nas1/data/backups/helix-restic`, encrypted
and deduplicated. That is the NAS's `/volume1/nas1/data/backups`, the same
directory as the hamology archives below; `config/infernalnexus.nix` names it
once for every Helix backup. Like the hamology archives, only the two newest
snapshots are kept (`backups.keep` in the same file drives both), so a file is
recoverable for about two nights after it changes or disappears. Each run ends
with a structural `restic check`. The run starts around 03:17,
yields to interactive work (nice 19, idle I/O) and catches up after a missed
night. GAMES_NVME and the data SSDs are not included.

This is the routine safety net. `helix-reinstall backup` remains the one-shot,
verified archive for a planned reinstall ([reinstall.md](reinstall.md)).

## One-time setup

The repository password never enters Git or the Nix store. Create it as root,
and store a copy in 1Password: without it the snapshots cannot be read.

```bash
# Refuses to run if a password already exists: replacing it makes every
# existing snapshot unreadable.
sudo sh -c 'set -o noclobber; umask 077; head -c 32 /dev/urandom | base64 > /etc/nixos/secrets/restic-helix'
sudo cat /etc/nixos/secrets/restic-helix   # save this in 1Password now
# Only for a brand-new repository, and only on the mounted share, never on the
# empty local directory underneath it:
ls /mnt/infernalnexus/nas1 >/dev/null && mountpoint -q /mnt/infernalnexus/nas1 &&
  sudo restic-helix init
sudo systemctl start restic-backups-helix.service
```

The service never creates the repository itself, so a wrong or unmigrated path
fails visibly instead of quietly starting an empty one.

Never regenerate the password once the repository exists. A run that reports
"wrong password or no key found" means the password file no longer matches the
repository: restore the saved password, or, if it
is lost, move `helix-restic` aside (its snapshots cannot be decrypted), then run
`sudo restic-helix init` and the service again to start a new repository.

## Moving from the old location

Until October 2026 Helix backups lived in `/mnt/infernalnexus/nas1/backup`.
Move them once, before switching to a configuration that uses
`data/backups`. Both moves are renames within the share, so they are instant;
`mv -T` refuses to nest a directory inside one that already exists.

```bash
cd /mnt/infernalnexus/nas1
mkdir -p data/backups/helix-reinstall
mv -T backup/helix-restic data/backups/helix-restic
for set in backup/helix-reinstall-*; do
  [[ -e $set ]] && mv -T -- "$set" "data/backups/helix-reinstall/${set#backup/}"
done
rmdir backup   # fails, and says why, if anything is left behind
```

The first run after the move prunes the repository to the two newest
snapshots; the older daily, weekly and monthly snapshots are deleted for good.

Until the password file exists the unit is skipped, not failed. If the NAS is
offline the run still starts and fails, so it raises a desktop alert (see
[operations.md](operations.md#failure-alerts)) and appears among failed units
in `helix-health`; the next night tries again.

## Restore drill

Run this every few months, and before relying on a backup:

```bash
sudo restic-helix snapshots
sudo restic-helix check --read-data-subset=5%
sudo restic-helix restore latest --target /tmp/restore-drill \
  --include /home/tristan/Documents
ls /tmp/restore-drill/home/tristan/Documents && sudo rm -rf /tmp/restore-drill
```

`restic-helix` is the NixOS wrapper that already knows the repository and
password. To recover a whole machine, restore into the new installation's
paths with `--target /`, then run `./scripts/rebuild.sh switch`.

## hamology service-state backups

`services/hamology-backup.nix` is a thin user timer: around 04:23 it runs
`~/Projects/hamology/scripts/hamology-backup --unattended --keep 2`, which
backs up Infernalnexus's service state on the NAS itself
(`/volume1/nas1/data/backups`) and keeps the two newest verified archives.
Nothing is copied to Helix. hamology owns what is captured and how it is
verified (see its `docs/operations.md`). Authorise the NAS once:

```bash
cd ~/Projects/hamology && scripts/hamology-backup --install-unattended
systemctl --user start hamology-backup.service   # first run
journalctl --user -u hamology-backup.service
```

The run never prompts: it needs an SSH key usable without a passphrase prompt
(or a loaded agent) and fails visibly if the NAS is offline or not authorised.
