{ ... }:

{
  imports = [ ../packages/gaming.nix ];

  # Steam's NixOS integration installs the client and its controller udev rules.
  programs.steam.enable = true;
  programs.gamemode.enable = true;
  hardware.graphics.enable32Bit = true;
  services.pipewire.alsa.support32Bit = true;
}
