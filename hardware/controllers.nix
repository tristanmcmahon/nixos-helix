{ lib, ... }:

{
  # The DualSense is supported by the upstream Sony HID driver over both USB
  # and Bluetooth. Load it eagerly so controller support does not depend on
  # Steam starting first or on a third-party kernel module.
  boot.kernelModules = [ "hid_playstation" ];

  # Xbox Bluetooth support was an experiment, not part of the Helix hardware
  # baseline. Keep xpadneo disabled and prevent its module from returning from
  # an older generation or an accidental future import.
  hardware.xpadneo.enable = lib.mkForce false;
  boot.blacklistedKernelModules = [ "hid_xpadneo" ];
}
