_:

{
  # GAMES_NVME was reformatted once, outside NixOS; rebuilds only mount it and
  # never partition or format it. The UUID is stable across NVMe device-name
  # changes, unlike paths such as /dev/nvme1n1p1.
  fileSystems."/mnt/games_nvme" = {
    device = "/dev/disk/by-uuid/d07ac88e-34f6-4d56-9941-5ceaf52fd6bb";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=5s"
    ];
  };

  # Periodically discard unused blocks on SSD/NVMe filesystems.
  services.fstrim.enable = true;
}
