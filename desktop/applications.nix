{ pkgs, ... }:

{
  # Plasma already supplies Dolphin and Ark; Firefox is the only additional
  # graphical application required by the base desktop.
  environment.systemPackages = [ pkgs.firefox ];
}
