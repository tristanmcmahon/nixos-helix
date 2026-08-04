_:

{
  # BlueZ backs Plasma System Settings and supports the onboard controller for input
  # devices, headsets, and other user-selected peripherals.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Pairing state is persistent system data under /var/lib/bluetooth; it is not
  # configuration source and must never be copied into this repository.
}
