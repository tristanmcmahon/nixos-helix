# Infernalnexus NAS

Helix exposes the Synology share `nas1` at the stable local path
`/mnt/infernalnexus/nas1`:

```text
Server:  192.168.1.8
Source:  //192.168.1.8/nas1
Mount:   /mnt/infernalnexus/nas1
SMB dialect: 2.0
Security:     NTLMSSP
```

SMB is the initial transport. A later NFS migration can retain the same local
path, but NFS support is intentionally deferred.

Real-hardware testing established that the Synology currently rejects SMB 3.0
and SMB 2.1. The mount deliberately pins `vers=2.0` with `sec=ntlmssp` rather
than relying on dialect negotiation. SMB1 remains prohibited. If the Synology
is later configured to support SMB3, test that configuration on real hardware
before changing the NixOS mount option.

## Credentials

Create the machine-local credentials file before activating the configuration:

```bash
sudo install -d -m 0700 /etc/nixos/secrets
sudo install -m 0600 /dev/null /etc/nixos/secrets/infernalnexus-smb
sudoedit /etc/nixos/secrets/infernalnexus-smb
```

Its contents use the CIFS credentials format:

```ini
username=REPLACE_WITH_SYNOLOGY_USERNAME
password=REPLACE_WITH_SYNOLOGY_PASSWORD
# Optional:
domain=WORKGROUP
```

The file must be owned by `root:root` with mode `0600`. It stays outside Git
and the Nix store; evaluation and builds do not require it to exist.

## Activation and use

After provisioning credentials, validate and activate normally:

```bash
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh test
# After real-hardware checks:
./scripts/rebuild.sh switch
```

Boot starts `mnt-infernalnexus-nas1.automount` without contacting the NAS.
Browsing the path or running this command triggers a network mount attempt:

```bash
ls /mnt/infernalnexus/nas1
```

The attempt times out after 15 seconds. An unused successful mount disconnects
after approximately ten minutes, and later access mounts it again.

Inspect the path and generated units with:

```bash
findmnt /mnt/infernalnexus/nas1
mountpoint /mnt/infernalnexus/nas1
systemctl status mnt-infernalnexus-nas1.automount
systemctl status mnt-infernalnexus-nas1.mount
journalctl -u mnt-infernalnexus-nas1.automount
journalctl -u mnt-infernalnexus-nas1.mount
```

Stop new automounts and cleanly detach an active mount with:

```bash
sudo systemctl stop mnt-infernalnexus-nas1.automount
sudo systemctl stop mnt-infernalnexus-nas1.mount
```

## Troubleshooting

The normal configuration uses systemd automount. For troubleshooting only, the
verified manual diagnostic mount command is:

```bash
sudo mount -t cifs //192.168.1.8/nas1 /mnt/infernalnexus/nas1 \
  -o credentials=/etc/nixos/secrets/infernalnexus-smb,uid="$(id -u)",gid="$(id -g)",file_mode=0664,dir_mode=0775,vers=2.0,sec=ntlmssp
```

After a failed attempt, inspect recent kernel messages with:

```bash
sudo dmesg | tail -n 30
```

Error 95 with “Dialect not supported by server” indicates an SMB dialect
mismatch. Do not use SMB1 as a fallback.

- Authentication errors: verify the credentials file's format, ownership, and
  mode, then inspect the mount unit journal. Do not print the file in logs.
- Network errors: confirm `ping 192.168.1.8` and TCP port 445 reach the NAS.
- Permission errors: local `uid`, `gid`, and mode options only present files as
  `tristan:users`; the Synology account still needs server-side access.
- A failed `ls` is expected when the NAS is offline. `nofail`, `_netdev`, and
  automount isolation keep that failure from destabilising boot or the desktop.
