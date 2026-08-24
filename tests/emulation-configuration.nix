{
  config,
  lib,
  pkgs,
  ...
}:

let
  mame0275 = pkgs.callPackage ../packages/mame-0275.nix { };
  romMounts = builtins.filter (mount: mount.where == "/mnt/infernalnexus/roms") config.systemd.mounts;
  romMount = builtins.head romMounts;
  romMountOptions = builtins.filter builtins.isString (builtins.split "," romMount.options);
  romAutomounts = builtins.filter (
    automount: automount.where == "/mnt/infernalnexus/roms"
  ) config.systemd.automounts;
in
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
        mame0275
        pkgs.igir
        pkgs.skyscraper
      ];
      message = "An enabled emulator or curation package is unavailable.";
    }
    {
      assertion = mame0275.version == "0.275";
      message = "The MAME launcher must match the NAS 0.275 collection and DATs.";
    }
    {
      assertion = builtins.length romMounts == 1;
      message = "The enabled module must define exactly one authoritative ROM mount.";
    }
    {
      assertion = romMount.what == "//192.168.1.8/roms" && romMount.type == "cifs";
      message = "The authoritative ROM mount must use the dedicated CIFS share.";
    }
    {
      assertion = builtins.all (option: builtins.elem option romMountOptions) [
        "credentials=/etc/nixos/secrets/infernalnexus-smb"
        "dir_mode=0555"
        "file_mode=0444"
        "ro"
      ];
      message = "The authoritative ROM mount must be credentialed and read-only.";
    }
    {
      assertion = !(builtins.elem "rw" romMountOptions);
      message = "The authoritative ROM mount must never be writable.";
    }
    {
      assertion = builtins.length romAutomounts == 1;
      message = "The authoritative ROM share must have exactly one automount.";
    }
    {
      assertion = builtins.hasAttr "helix-emulation-prepare" config.systemd.user.services;
      message = "The enabled module must install its NAS preparation service.";
    }
  ];
}
