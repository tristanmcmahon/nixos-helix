{ ... }:

{
  imports = [ ../packages/gaming.nix ];

  # Steam's NixOS integration supplies its runtime and controller udev rules.
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  hardware.graphics.enable32Bit = true;
}
