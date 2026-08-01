{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    steam
    mangohud
    gamescope
    lutris
  ];
}
