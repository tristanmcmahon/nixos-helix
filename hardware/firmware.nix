_:

{
  # Wi-Fi, Bluetooth, audio DSPs, GPUs, and motherboard devices often require
  # redistributable firmware that cannot be shipped under a fully free licence.
  # Enabling the catalogue does not guess which blobs are needed: the kernel
  # requests firmware only for hardware it actually detects.
  hardware.enableRedistributableFirmware = true;

  # CPU microcode is vendor-specific. The generated hardware module should set
  # exactly one of hardware.cpu.intel.updateMicrocode or
  # hardware.cpu.amd.updateMicrocode after the CPU has been detected.
}
