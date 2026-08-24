{ pkgs, ... }:

let
  host = import ../config/host.nix;
in
{
  # mount.cifs is a filesystem helper, not an interactive workstation tool.
  system.fsPackages = [ pkgs.cifs-utils ];

  # Native units are static closure artifacts, unlike units generated from
  # fstab during boot. This makes live activation reliable without touching
  # the optional NAS until the path is accessed.
  systemd.mounts = [
    {
      description = "Infernalnexus NAS share";
      what = "//192.168.1.8/nas1";
      where = "/mnt/infernalnexus/nas1";
      type = "cifs";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      options = builtins.concatStringsSep "," [
        # This runtime-only file remains outside Git and the Nix store.
        "credentials=/etc/nixos/secrets/infernalnexus-smb"
        "uid=${host.user}"
        "gid=${host.userGroup}"
        "dir_mode=0775"
        "file_mode=0664"

        # Real hardware rejects newer dialects. Re-test before raising this
        # pin after the Synology SMB maximum is changed to SMB3.
        "vers=2.0"
        "sec=ntlmssp"
      ];

      mountConfig.TimeoutSec = "15s";
    }
  ];

  systemd.automounts = [
    {
      description = "Automount Infernalnexus NAS share";
      where = "/mnt/infernalnexus/nas1";
      wantedBy = [ "multi-user.target" ];
      automountConfig = {
        TimeoutIdleSec = "10min";
        DirectoryMode = "0755";
      };
    }
  ];
}
