# Routine backups

`services/backup.nix` takes a nightly restic snapshot of the state a rebuild
cannot recreate:

- `/home/tristan`, except caches, Trash, the Steam library and build outputs;
- `/etc/nixos/secrets`;
- `/etc/ssh` (host keys);
- `/etc/NetworkManager/system-connections`.

Snapshots go to `/mnt/infernalnexus/nas1/backup/helix-restic`, encrypted and
deduplicated. Seven daily, five weekly and twelve monthly snapshots are kept,
and each run ends with a structural `restic check`. The run starts around 03:17,
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
sudo systemctl start restic-backups-helix.service   # first run creates the repository
```

Never regenerate the password once the repository exists. A run that reports
"wrong password" followed by "config file already exists" means the password
file no longer matches the repository: restore the saved password, or, if it
is lost, move `helix-restic` aside (its snapshots cannot be decrypted) and run
the service again to start a new repository.

Until the password file exists the unit is skipped, not failed. If the NAS is
offline the run fails, appears among failed units in `helix-health`, and runs
again after the next boot.

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
