{ pkgs, ... }:

let
  zen-browser = pkgs.callPackage ../packages/zen-browser.nix { };
in
{
  # Plasma already supplies Dolphin and Ark; these are the additional
  # graphical applications required by the base desktop.
  environment.systemPackages = [
    # Keep both the proprietary Chrome build and the fully open Chromium build
    # available for browser compatibility testing.
    pkgs.google-chrome
    pkgs.chromium
    zen-browser
    pkgs.firefox
    pkgs.obsidian
  ];
}
