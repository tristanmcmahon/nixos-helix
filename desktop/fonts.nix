{ pkgs, ... }:

{
  fonts = {
    packages = [
      # Clear and highly readable; the workstation default.
      pkgs.nerd-fonts.jetbrains-mono
      # A compact, modern alternative.
      pkgs.maple-mono.NF
      # A dense alternative for higher information density.
      pkgs.nerd-fonts.iosevka
    ];

    fontconfig.defaultFonts.monospace = [ "JetBrainsMono Nerd Font Mono" ];
  };
}
