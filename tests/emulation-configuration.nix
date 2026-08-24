{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../profiles/emulation.nix ];

  helix.emulation.enable = true;
  nixpkgs.config.allowUnfree = true;
  programs.steam.enable = true;

  users.users.tristan = {
    isNormalUser = true;
    extraGroups = [ "users" ];
  };

  # Minimal CI host facts. This configuration intentionally excludes every
  # unrelated Helix profile, package pin, desktop, and reinstall fixture.
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
  };
  networking.hostName = "helix-emulation-ci";
  system.stateVersion = "26.05";

  assertions = [
    {
      assertion = lib.all (package: package != null) [
        pkgs.pcsx2
        pkgs.rpcs3
        pkgs.shadps4
        pkgs.mame
        pkgs.igir
        pkgs.skyscraper
      ];
      message = "An enabled emulator or curation package is unavailable.";
    }
    {
      assertion = builtins.any (
        mount: mount.where == "/mnt/infernalnexus/roms" && mount.what == "//192.168.1.8/roms"
      ) config.systemd.mounts;
      message = "The enabled module must expose the authoritative ROM share.";
    }
    {
      assertion = builtins.any (
        automount: automount.where == "/mnt/infernalnexus/roms"
      ) config.systemd.automounts;
      message = "The authoritative ROM share must be automounted.";
    }
  ];
}
