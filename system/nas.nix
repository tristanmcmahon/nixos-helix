{ pkgs, ... }:

let
  infernalnexus = import ../config/infernalnexus.nix;
  share = infernalnexus.shares.nas1;
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
      what = share.source;
      where = share.mountPoint;
      type = "cifs";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      options = builtins.concatStringsSep "," [
        # This runtime-only file remains outside Git and the Nix store.
        "credentials=${infernalnexus.credentialsFile}"
        "uid=${infernalnexus.user}"
        "gid=${infernalnexus.group}"
        "dir_mode=0775"
        "file_mode=0664"

        # Real hardware rejects newer dialects. Re-test before raising this
        # pin after the Synology SMB maximum is changed to SMB3.
        "vers=${infernalnexus.smbVersion}"
        "sec=${infernalnexus.security}"
      ];

      mountConfig.TimeoutSec = infernalnexus.mountTimeout;
    }
  ];

  systemd.automounts = [
    {
      description = "Automount Infernalnexus NAS share";
      where = share.mountPoint;
      wantedBy = [ "multi-user.target" ];
      automountConfig = {
        TimeoutIdleSec = infernalnexus.idleTimeout;
        DirectoryMode = "0755";
      };
    }
  ];
}
