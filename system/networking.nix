{ ... }:

{
  networking = {
    hostName = "helix";

    # NetworkManager handles Ethernet and Wi-Fi and integrates with Plasma
    # System Settings. Interface names and access-point credentials remain runtime
    # state, so neither is guessed or committed here.
    networkmanager.enable = true;

    # Keep NixOS' stateful firewall even though no server service is enabled.
    # Desktop clients generally need no inbound port exceptions.
    firewall.enable = true;
  };

  # Do not also enable networking.wireless: running wpa_supplicant separately
  # would compete with NetworkManager for the same Wi-Fi controller.
}
