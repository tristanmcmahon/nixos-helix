{ pkgs, ... }:

let
  gridplayer = pkgs.callPackage ./gridplayer.nix { };
in
{
  # Consumption clients only: Helix does not host or automate media services.
  environment.systemPackages = [
    pkgs.spotify
    pkgs.vlc
    pkgs.mpv
    pkgs.haruna
    pkgs.strawberry
    pkgs.plex-desktop
    gridplayer
  ];
}
