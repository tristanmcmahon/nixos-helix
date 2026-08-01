{ ... }:

{
  # Helix is installed in UEFI mode using systemd-boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 5;

  powerManagement.enable = true;
}
