{ ... }:

{
  # GDM integrates GNOME login, session locking, and Wayland correctly. No
  # automatic login is configured, so an account credential is always needed.
  services.displayManager.gdm.enable = true;

  # GNOME 50 no longer supports disabling GDM's Wayland backend, so current
  # NixOS deliberately has no gdm.wayland policy switch. NVIDIA DRM modesetting
  # in hardware/nvidia.nix supplies the prerequisite for the Wayland session.

  services.desktopManager.gnome.enable = true;

  # udisks2 performs policy-controlled mounts, while GVfs exposes those mounts
  # and MTP/camera devices in Files. Together they provide removable-storage
  # support without hard-coding device nodes or adding entries to /etc/fstab.
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  # GNOME upstream treats several network-facing components as desktop
  # defaults. Helix starts without discovery, media sharing, file sharing, or
  # remote-control services; they can be enabled later for a concrete need.
  services.avahi.enable = false;
  services.dleyna.enable = false;
  services.gnome.gnome-remote-desktop.enable = false;
  services.gnome.gnome-user-share.enable = false;
  services.gnome.rygel.enable = false;

  # GNOME enables bolt by default, but a Thunderbolt/USB4 security controller
  # has not yet been detected. Enable this after `boltctl` or the PCI inventory
  # confirms that Helix actually has one.
  services.hardware.bolt.enable = false;

  # GNOME games and developer utilities are separate module groups and are not
  # part of a minimal workstation installation.
  services.gnome.games.enable = false;
  services.gnome.core-developer-tools.enable = false;
}
