{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  cfg = config.helix.emulation;
  infernalnexus = import ../../config/infernalnexus.nix;
  helix = import ../../config/helix.nix;
  helixLib = import ../../lib/helix.nix { inherit lib pkgs utils; };
  roms = helixLib.mkInfernalnexusShare {
    share = infernalnexus.shares.roms;
    description = "authoritative ROM collection";
    readOnly = true;
  };
in
{
  config = lib.mkIf cfg.enable {
    # tfpga and Helix share one authoritative ROM collection. It is exposed
    # only while this module is enabled and is deliberately read-only here.
    system.fsPackages = [ pkgs.cifs-utils ];

    systemd = {
      inherit (roms) mounts automounts;
      services.helix-emulation-storage = helixLib.mkMountedDirectory {
        description = "Create the emulation workspace on GAMES_NVME";
        inherit (helix.gamesNvme) mountPoint;
        path = "${helix.gamesNvme.mountPoint}/emulation";
        owner = helix.user;
        inherit (helix) group;
        mode = "0775";
      };
    };
  };
}
