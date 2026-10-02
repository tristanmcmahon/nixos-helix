{
  lib,
  pkgs,
  utils,
  ...
}:

let
  helix = import ../config/helix.nix;
  helixLib = import ../lib/helix.nix { inherit lib pkgs utils; };
  mountOptions = [
    "noatime"
    "nofail"
    "x-systemd.device-timeout=5s"
  ];
  games = helix.gamesNvme.mountPoint;
in
{
  # GAMES_NVME was reformatted once, outside NixOS; rebuilds only mount it and
  # never partition or format it.
  fileSystems = {
    ${games} = {
      device = "/dev/disk/by-uuid/${helix.gamesNvme.uuid}";
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
    }) helix.ssds
  );

  # Each optional disk initialises independently and only when it is mounted.
  systemd.services = lib.listToAttrs (
    map (ssd: {
      name = "helix-storage-${ssd.id}-directories";
      value = helixLib.mkMountedDirectory {
        description = "Create the ${ssd.label} data directory";
        inherit (ssd) mountPoint;
        path = "${ssd.mountPoint}/data";
        owner = helix.user;
        inherit (helix) group;
        mode = "0775";
      };
    }) helix.ssds
  );

  # Periodically discard unused blocks on SSD/NVMe filesystems.
  services.fstrim.enable = true;
}
