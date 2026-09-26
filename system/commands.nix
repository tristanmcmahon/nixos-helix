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
      coreutils
      deadnix
      gawk
      git
      nix
      nix-output-monitor
      nixfmt
      nvd
      shellcheck
      statix
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
