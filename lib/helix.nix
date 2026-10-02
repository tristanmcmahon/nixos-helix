# Small helpers for patterns that Helix repeats across modules.
{
  lib,
  pkgs,
  utils ? null,
}:

let
  infernalnexus = import ../config/infernalnexus.nix;
in
{
  # A oneshot that creates a directory on an optional disk, only after
  # positively verifying the disk is mounted. Without the mount it is skipped,
  # so a missing disk can never cause writes to the root filesystem.
  mkMountedDirectory =
    {
      description,
      mountPoint,
      path,
      owner,
      group,
      mode,
    }:
    let
      mountUnit = "${utils.escapeSystemdPath mountPoint}.mount";
    in
    {
      inherit description;
      wantedBy = [ "multi-user.target" ];
      wants = [ mountUnit ];
      after = [ mountUnit ];
      unitConfig.ConditionPathIsMountPoint = mountPoint;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg mountPoint}
        ${pkgs.coreutils}/bin/install -d -o ${owner} -g ${group} -m ${mode} \
          ${lib.escapeShellArg path}
      '';
    };

  # Native mount and automount units for an Infernalnexus share. Native units
  # are static closure artifacts, unlike fstab-generated ones, so live
  # activation is reliable and the optional NAS is untouched until accessed.
  mkInfernalnexusShare =
    {
      share,
      description,
      readOnly,
    }:
    {
      mounts = [
        {
          description = "Infernalnexus ${description}";
          what = share.source;
          where = share.mountPoint;
          type = "cifs";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          options = builtins.concatStringsSep "," (
            [
              # This runtime-only file remains outside Git and the Nix store.
              "credentials=${infernalnexus.credentialsFile}"
              "uid=${infernalnexus.user}"
              "gid=${infernalnexus.group}"
              (if readOnly then "dir_mode=0555" else "dir_mode=0775")
              (if readOnly then "file_mode=0444" else "file_mode=0664")

              # Real hardware rejects newer dialects. Re-test before raising
              # this pin after the Synology SMB maximum is changed to SMB3.
              "vers=${infernalnexus.smbVersion}"
              "sec=${infernalnexus.security}"
            ]
            ++ lib.optional readOnly "ro"
          );
          mountConfig.TimeoutSec = infernalnexus.mountTimeout;
        }
      ];
      automounts = [
        {
          description = "Automount Infernalnexus ${description}";
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
