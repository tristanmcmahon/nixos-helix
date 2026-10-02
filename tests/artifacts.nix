# Build artifacts the --full closure checks inspect, from one evaluation of the
# canonical configuration, as one directory of named links so the checks never
# depend on the order or number of nix-build output lines.
let
  system = import <nixpkgs/nixos> { configuration = ../configuration.nix; };
  inherit (system) config pkgs;
in
pkgs.linkFarm "helix-check-artifacts" [
  {
    name = "hyprland.conf";
    path = config.environment.etc."hypr/helix.conf".source;
  }
  {
    name = "session-data";
    path = config.services.displayManager.sessionData.desktops;
  }
  {
    name = "1password-gui";
    path = config.programs._1password-gui.package;
  }
  {
    name = "1password-cli";
    path = config.programs._1password.package;
  }
]
