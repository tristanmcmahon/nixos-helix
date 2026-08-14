{ pkgs, ... }:

{
  # GAMES_NVME was reformatted once, outside NixOS; rebuilds only mount it and
  # never partition or format it. The UUID is stable across NVMe device-name
  # changes, unlike paths such as /dev/nvme1n1p1.
  fileSystems = {
    "/mnt/games_nvme" = {
      device = "/dev/disk/by-uuid/d07ac88e-34f6-4d56-9941-5ceaf52fd6bb";
      fsType = "ext4";
      options = [
        "noatime"
        "nofail"
        "x-systemd.device-timeout=5s"
      ];
    };

    "/mnt/helix_ssd_a" = {
      device = "/dev/disk/by-label/HELIX_SSD_A";
      fsType = "ext4";
      options = [
        "noatime"
        "nofail"
        "x-systemd.device-timeout=5s"
      ];
    };

    "/mnt/helix_ssd_b" = {
      device = "/dev/disk/by-label/HELIX_SSD_B";
      fsType = "ext4";
      options = [
        "noatime"
        "nofail"
        "x-systemd.device-timeout=5s"
      ];
    };

    "/mnt/helix_ssd_c" = {
      device = "/dev/disk/by-label/HELIX_SSD_C";
      fsType = "ext4";
      options = [
        "noatime"
        "nofail"
        "x-systemd.device-timeout=5s"
      ];
    };
  };

  # Create only the owned data roots after systemd has made all mounts available.
  systemd.services.helix-storage-directories = {
    description = "Create Helix SSD data directories";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = [
      "/mnt/helix_ssd_a"
      "/mnt/helix_ssd_b"
      "/mnt/helix_ssd_c"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.util-linux}/bin/mountpoint -q /mnt/helix_ssd_a
      ${pkgs.util-linux}/bin/mountpoint -q /mnt/helix_ssd_b
      ${pkgs.util-linux}/bin/mountpoint -q /mnt/helix_ssd_c
      ${pkgs.coreutils}/bin/install -d -o tristan -g users -m 0775 /mnt/helix_ssd_a/data
      ${pkgs.coreutils}/bin/install -d -o tristan -g users -m 0775 /mnt/helix_ssd_b/data
      ${pkgs.coreutils}/bin/install -d -o tristan -g users -m 0775 /mnt/helix_ssd_c/data
    '';
  };

  # Periodically discard unused blocks on SSD/NVMe filesystems.
  services.fstrim.enable = true;
}
