# PLACEHOLDER -- DO NOT DEPLOY THIS FILE.
#
# `nixos-generate-config` creates this module from the real installation. It
# normally contains filesystem UUIDs, the boot filesystem, initrd modules,
# platform information, swap devices, and CPU-vendor microcode settings.
# None of those values can be inferred safely from the requested workstation
# design, so this repository intentionally contains an empty, syntactically
# valid stand-in.
#
# Review the generated module together with the inventory for the CPU/chipset,
# NVMe/storage controllers, USB controllers, Ethernet, Wi-Fi, audio, webcam,
# microphone, and any other PCI/USB devices. Ordinary hot-plug peripherals do
# not need fixed identifiers, but every device should have a bound kernel driver
# and every boot-critical controller must be available in the initrd.
#
# Before the first rebuild, preserve the existing
# /etc/nixos/hardware-configuration.nix or replace this file with output from:
#
#   sudo nixos-generate-config --show-hardware-config
#
# Review the generated result; do not hand-copy identifiers from another host.
{ ... }:

{
}
