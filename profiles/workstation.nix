{ lib, ... }:

{
  # Daily interactive tools, hardware diagnostic clients and media clients.
  # Font policy is owned once by desktop/fonts.nix.
  imports = [
    ./workstation/tools.nix
    ./workstation/hardware-tools.nix
    ./workstation/media.nix
  ];

  options.helix.workstation.enable = lib.mkEnableOption "the daily workstation toolset";
}
