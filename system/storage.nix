{
  lib,
  pkgs,
  utils,
  ...
}:

let
  localSsds = import ./local-ssds.nix;
  mountOptions = [
    "noatime"
    "nofail"
    "x-systemd.device-timeout=5s"
  ];
in
{
  # GAMES_NVME was reformatted once, outside NixOS; rebuilds only mount it and
  # never partition or format it. The UUID is stable across NVMe device-name
  # changes, unlike paths such as /dev/nvme1n1p1.
  fileSystems = {
    "/mnt/games_nvme" = {
      device = "/dev/disk/by-uuid/d07ac88e-34f6-4d56-9941-5ceaf52fd6bb";
      fsType = "ext4";
      options = mountOptions;
    };
  }
  // lib.listToAttrs (
    map (ssd: {
      name = ssd.mountPoint;
      value = {
        device = "/dev/disk/by-label/${ssd.label}";
        fsType = "ext4";
        options = mountOptions;
      };
    }) localSsds
  );

  # Each optional disk initialises independently and only when it is mounted.
  systemd.services =
    lib.listToAttrs (
      map (ssd: {
        name = "helix-storage-${ssd.id}-directories";
        value = {
          description = "Create the ${ssd.label} data directory";
          wantedBy = [ "multi-user.target" ];
          wants = [ "${utils.escapeSystemdPath ssd.mountPoint}.mount" ];
          after = [ "${utils.escapeSystemdPath ssd.mountPoint}.mount" ];
          unitConfig.ConditionPathIsMountPoint = ssd.mountPoint;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg ssd.mountPoint}
            ${pkgs.coreutils}/bin/install -d -o tristan -g users -m 0775 \
              ${lib.escapeShellArg "${ssd.mountPoint}/data"}
          '';
        };
      }) localSsds
    )
    // {
      helix-ollama-model-storage = {
        description = "Create the Ollama model store on GAMES_NVME";
        wantedBy = [ "multi-user.target" ];
        wants = [ "mnt-games_nvme.mount" ];
        after = [ "mnt-games_nvme.mount" ];
        unitConfig.ConditionPathIsMountPoint = "/mnt/games_nvme";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.util-linux}/bin/mountpoint -q /mnt/games_nvme
          ${pkgs.coreutils}/bin/install -d -o ollama -g ollama -m 0750 \
            /mnt/games_nvme/ollama/models
        '';
      };

      helix-doom-storage = {
        description = "Create the Doom library on GAMES_NVME";
        wantedBy = [ "multi-user.target" ];
        wants = [ "mnt-games_nvme.mount" ];
        after = [ "mnt-games_nvme.mount" ];
        unitConfig.ConditionPathIsMountPoint = "/mnt/games_nvme";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${pkgs.util-linux}/bin/mountpoint -q /mnt/games_nvme
          ${pkgs.coreutils}/bin/install -d -o tristan -g users -m 0775 \
            /mnt/games_nvme/doom
        '';
      };
    };

  # Periodically discard unused blocks on SSD/NVMe filesystems.
  services.fstrim.enable = true;
}
