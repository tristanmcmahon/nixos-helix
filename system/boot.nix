{ ... }:

{
  # Five seconds leaves time to choose an older generation after a bad change
  # without making every normal boot feel slow. This is loader-neutral policy;
  # the generated hardware configuration must still select the actual loader.
  boot.loader.timeout = 5;

  # Keep the standard system suspend/resume machinery available. No sleep mode
  # or resume device is forced until the inventory and real suspend tests show
  # that this motherboard needs a specific workaround.
  powerManagement.enable = true;

  # PLACEHOLDER: restore the installation's verified boot-loader settings here
  # before rebuilding. BIOS/UEFI mode, systemd-boot versus GRUB, Secure Boot,
  # encryption, swap/resume devices, and initrd modules are installation facts;
  # this repository cannot select them without inspecting the target.
}
