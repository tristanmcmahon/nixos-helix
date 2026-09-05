{ pkgs, ... }:

let
  helixHealth = pkgs.writeShellApplication {
    name = "helix-health";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      gawk
      nix
      procps
      systemd
      util-linux
      openclaw
    ];
    text = builtins.readFile ../scripts/helix-health.sh;
  };
  helixUpdate = pkgs.writeShellApplication {
    name = "helix-update";
    runtimeInputs = with pkgs; [
      gawk
      git
      nix
      nix-output-monitor
      nvd
    ];
    text = builtins.readFile ../scripts/helix-update.sh;
  };
in
{
  environment.systemPackages = [
    helixHealth
    helixUpdate
  ];
}
