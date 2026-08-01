{ pkgs, ... }:

{
  # Plasma already supplies Dolphin and Ark; these are the additional
  # graphical applications required by the base desktop.
  environment.systemPackages = [
    pkgs.firefox
    pkgs.obsidian
  ];
}
