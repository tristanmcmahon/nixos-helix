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

The share uses native NixOS `systemd.mounts` and `systemd.automounts`, not an
fstab-generated automount. Both unit files therefore exist statically in the
system closure, while the CIFS mount itself remains strictly on demand. Before
first access, `active (waiting)` is the correct automount state. The credentials
file is optional for evaluation, building, and activation, but required for
access. Static configuration and dry activation validate unit construction
only; sustained real-hardware access remains a qualification step.

Real-hardware testing established that the Synology currently rejects SMB 3.0
and SMB 2.1. SMB2 with NTLMSSP gets past dialect negotiation, and brief
real-hardware access has succeeded. Sustained stability still requires runtime
qualification. The mount deliberately pins `vers=2.0` with `sec=ntlmssp`
rather than relying on negotiation. SMB1 remains prohibited. If the Synology is
later configured to support SMB3, test it on real hardware before changing the
NixOS mount option.

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

After temporary activation, Tristan can perform a sustained read-only test
without creating or changing NAS data:

```bash
find /mnt/infernalnexus/nas1 -xdev -type f -readable -print0 \
  | head -z -n 1000 \
  | xargs -0 -r sha256sum > /dev/null
findmnt /mnt/infernalnexus/nas1
```

This intentionally triggers the automount. Run it only during the manual
runtime qualification window, never as an automated repository check.

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

An earlier fstab-generated implementation caused a real persistent activation
to fail after `/etc` setup with:

```text
Failed to open unit file .../etc/systemd/system/mnt-infernalnexus-nas1.automount
No such file or directory (os error 2)
```

The generator-created unit was absent from the new closure during live switch.
Native static units repair that mismatch; rebooting is not a workaround for a
failed `switch`.

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
- A failed `ls` is expected when the NAS is offline. Only the automount is
  pulled into boot; explicit network ordering and on-demand isolation keep an
  absent NAS from destabilising boot or the desktop.
