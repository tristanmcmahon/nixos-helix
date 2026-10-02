{ lib, pkgs, ... }:

let
  infernalnexus = import ../config/infernalnexus.nix;
  helixLib = import ../lib/helix.nix { inherit lib pkgs; };
  nas = helixLib.mkInfernalnexusShare {
    share = infernalnexus.shares.nas1;
    description = "NAS share";
    readOnly = false;
  };
in
{
  # mount.cifs is a filesystem helper, not an interactive workstation tool.
  system.fsPackages = [ pkgs.cifs-utils ];

  systemd = { inherit (nas) mounts automounts; };
}
