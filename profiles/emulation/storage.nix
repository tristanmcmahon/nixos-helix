{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.emulation;
  infernalnexus = import ../../config/infernalnexus.nix;
  helixLib = import ../../lib/helix.nix { inherit lib pkgs; };
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

    systemd = { inherit (roms) mounts automounts; };
  };
}
