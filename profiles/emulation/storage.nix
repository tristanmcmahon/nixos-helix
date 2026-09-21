{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.emulation;
  infernalnexus = import ../../config/infernalnexus.nix;
  share = infernalnexus.shares.roms;
in
{
  config = lib.mkIf cfg.enable {
    # tfpga and Helix share one authoritative ROM collection. It is exposed
    # only while this module is enabled and is deliberately read-only here.
    system.fsPackages = [ pkgs.cifs-utils ];

    systemd.mounts = [
      {
        description = "Infernalnexus authoritative ROM collection";
        what = share.source;
        where = share.mountPoint;
        type = "cifs";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        options = builtins.concatStringsSep "," [
          "credentials=${infernalnexus.credentialsFile}"
          "uid=${infernalnexus.user}"
          "gid=${infernalnexus.group}"
          "dir_mode=0555"
          "file_mode=0444"
          "vers=${infernalnexus.smbVersion}"
          "sec=${infernalnexus.security}"
          "ro"
        ];
        mountConfig.TimeoutSec = infernalnexus.mountTimeout;
      }
    ];

    systemd.automounts = [
      {
        description = "Automount Infernalnexus ROM collection";
        where = share.mountPoint;
        wantedBy = [ "multi-user.target" ];
        automountConfig = {
          TimeoutIdleSec = infernalnexus.idleTimeout;
          DirectoryMode = "0755";
        };
      }
    ];
  };
}
