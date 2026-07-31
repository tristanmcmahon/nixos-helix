{ pkgs, ... }:

{
  # Keep the useful GNOME core: Console, Files, Text Editor, Settings, Disks,
  # Calculator, System Monitor, Logs, Papers, Loupe, Snapshot, and key storage.
  # Remove optional personal-information, media, weather, remote-connection,
  # tour, and help applications that have no initial requirement.
  environment.gnome.excludePackages = with pkgs; [
    decibels
    epiphany
    gnome-calendar
    gnome-characters
    gnome-clocks
    gnome-connections
    gnome-contacts
    gnome-font-viewer
    gnome-maps
    gnome-music
    gnome-tecla
    gnome-tour
    gnome-weather
    showtime
    simple-scan
    yelp
  ];

  environment.systemPackages = with pkgs; [
    # One mainstream browser replaces GNOME Web.
    firefox

    # Nautilus uses File Roller for creating and extracting archives.
    file-roller
  ];
}
