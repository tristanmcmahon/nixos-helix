{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    adwsteamgtk
    mangohud
  ];
}
