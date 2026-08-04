{ ... }:

{
  # The attached original Corsair K70 RGB reports USB ID 1b1c:1b13. Use the
  # supported NixOS module so its daemon, package, and device rules have one
  # owner. The unmodified 26.05 package provides its daemon, GUI, service, and
  # udev rules, so Helix carries no package override.
  hardware.ckb-next.enable = true;
}
