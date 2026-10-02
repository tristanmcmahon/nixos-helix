# Helix host facts. Modules and tests import this instead of repeating them;
# scripts that run from the checkout read it with nix-instantiate.
let
  user = "tristan";
  home = "/home/${user}";
in
{
  inherit user home;
  group = "users";
  configHome = "${home}/.config";
  checkout = "${home}/Projects/nixos-helix";

  # GAMES_NVME was reformatted once, outside NixOS; rebuilds only mount it.
  # The UUID is stable across NVMe device-name changes.
  gamesNvme = {
    uuid = "d07ac88e-34f6-4d56-9941-5ceaf52fd6bb";
    mountPoint = "/mnt/games_nvme";
  };

  # Optional data SSDs, mounted by label and identified by serial.
  ssds = [
    {
      id = "a";
      label = "HELIX_SSD_A";
      mountPoint = "/mnt/helix_ssd_a";
      serial = "S2PWNX0HA06906Y";
    }
    {
      id = "b";
      label = "HELIX_SSD_B";
      mountPoint = "/mnt/helix_ssd_b";
      serial = "S21HNXBG406937R";
    }
    {
      id = "c";
      label = "HELIX_SSD_C";
      mountPoint = "/mnt/helix_ssd_c";
      serial = "S1DHNSADB22089E";
    }
  ];
}
