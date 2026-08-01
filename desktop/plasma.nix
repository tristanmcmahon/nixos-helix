{ pkgs, ... }:

{
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Helix does not use the KDE PIM suite or desktop-hosted remote access. Ark,
  # Dolphin, Spectacle, portals, removable media, and wallet support remain.
  programs.kde-pim.enable = false;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    discover
    elisa
    krdp
  ];
}
