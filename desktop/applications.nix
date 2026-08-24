{ pkgs, ... }:

let
  chatgpt = pkgs.callPackage ../packages/chatgpt.nix { };
  zen-browser = pkgs.callPackage ../packages/zen-browser.nix { };
in
{
  # Plasma already supplies Dolphin and Ark; these are the additional
  # graphical applications required by the base desktop.
  environment.systemPackages = [
    # Chrome remains separate from Chromium, which is owned by programs.chromium.
    pkgs.google-chrome
    chatgpt
    zen-browser
    pkgs.obsidian
    pkgs.signal-desktop
    pkgs.pidgin
  ];
}
