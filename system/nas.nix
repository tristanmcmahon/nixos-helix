{ pkgs, ... }:

{
  # mount.cifs is a filesystem helper, not an interactive workstation tool.
  system.fsPackages = [ pkgs.cifs-utils ];

  # Keep this local path stable if the transport changes from SMB to NFS later.
  fileSystems."/mnt/infernalnexus/nas1" = {
    device = "//192.168.1.8/nas1";
    fsType = "cifs";
    options = [
      # The NAS is optional: boot creates only an automount, and first access
      # performs a bounded network mount. Idle mounts disconnect after 10 min.
      "_netdev"
      "nofail"
      "x-systemd.automount"
      "x-systemd.mount-timeout=15s"
      "x-systemd.idle-timeout=10min"

      # Real-hardware testing showed that the current Synology SMB service
      # rejects newer dialects. SMB 2.0 with NTLMSSP is verified working;
      # revisit this pin if the Synology SMB maximum is later raised to SMB3.
      "vers=2.0"
      "sec=ntlmssp"

      # This runtime-only file deliberately remains outside Git and the Nix
      # store. Its absence does not prevent evaluation or building.
      "credentials=/etc/nixos/secrets/infernalnexus-smb"

      # These options control local presentation only; the NAS account's
      # server-side permissions remain authoritative.
      "uid=tristan"
      "gid=users"
      "dir_mode=0775"
      "file_mode=0664"
    ];
  };
}
