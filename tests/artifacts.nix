# Build artifacts the --full closure checks inspect, from one evaluation of the
# canonical configuration (rather than one evaluation per artifact).
let
  system = import <nixpkgs/nixos> { configuration = ../configuration.nix; };
  inherit (system) config;
in
{
  hyprlandConfig = config.environment.etc."hypr/helix.conf".source;
  sessionData = config.services.displayManager.sessionData.desktops;
  onepasswordGui = config.programs._1password-gui.package;
  onepasswordCli = config.programs._1password.package;
}
