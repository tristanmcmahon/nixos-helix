_:

{
  networking = {
    hostName = "helix";

    # NetworkManager handles Ethernet and Wi-Fi and integrates with Plasma
    # System Settings. Interface names and access-point credentials remain runtime
    # state, so neither is guessed or committed here.
    networkmanager = {
      enable = true;

      # Helix is the first client for the Pi-hole on infernalnexus. Keep DHCP
      # for addresses/routes, but prevent DHCP-provided DNS from bypassing the
      # Pi-hole. If infernalnexus DNS is unavailable, Helix DNS should fail
      # visibly rather than silently falling back around the test.
      dns = "none";
    };

    nameservers = [ "192.168.1.8" ];

    # Keep NixOS' stateful firewall. The OpenSSH module owns the sole inbound
    # exception for TCP port 22; desktop clients need no additional exceptions.
    firewall.enable = true;
  };

  # Do not also enable networking.wireless: running wpa_supplicant separately
  # would compete with NetworkManager for the same Wi-Fi controller.
}
