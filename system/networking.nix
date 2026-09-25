{
  config,
  lib,
  ...
}:

let
  cfg = config.helix.networking.pihole;
in
{
  options.helix.networking.pihole = {
    enable = lib.mkEnableOption "Pi-hole DNS on infernalnexus for Helix";

    address = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.8";
      description = "DNS server address for the Pi-hole used by Helix.";
    };
  };

  config = lib.mkMerge [
    {
      networking = {
        hostName = "helix";

        # NetworkManager handles Ethernet and Wi-Fi and integrates with Plasma
        # System Settings. Interface names and access-point credentials remain
        # runtime state, so neither is guessed or committed here.
        networkmanager.enable = true;

        # Keep NixOS' stateful firewall. The OpenSSH module owns the sole inbound
        # exception for TCP port 22; desktop clients need no additional exceptions.
        firewall.enable = true;
      };

      # Do not also enable networking.wireless: running wpa_supplicant separately
      # would compete with NetworkManager for the same Wi-Fi controller.
    }

    (lib.mkIf cfg.enable {
      networking = {
        # Keep DHCP for addresses/routes, but stop NetworkManager from importing
        # DHCP-provided DNS that could bypass the Pi-hole.
        networkmanager.dns = "none";
        nameservers = [ cfg.address ];
      };
    })
  ];
}
