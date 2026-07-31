{ ... }:

{
  # A NixOS configuration is assembled by importing modules. Each module below
  # contributes option values to one combined system configuration; file order
  # does not imply service start order.
  imports = [
    # This file is generated on Helix and owns filesystems, boot-critical
    # modules, and CPU microcode selection. See its placeholder before rebuild.
    ./hardware-configuration.nix

    ./hardware/nvidia.nix
    ./hardware/audio.nix
    ./hardware/bluetooth.nix
    ./hardware/firmware.nix

    ./desktop/gnome.nix
    ./desktop/applications.nix

    ./system/boot.nix
    ./system/networking.nix
    ./system/users.nix
    ./system/locale.nix
    ./system/packages.nix

    ./services/maintenance.nix
  ];

  # NVIDIA's user-space driver is redistributable but not free software, so
  # Nixpkgs will refuse to evaluate it unless unfree packages are permitted.
  # This does not install CUDA or any other compute/development stack.
  nixpkgs.config.allowUnfree = true;

  # This value is the compatibility floor for persistent state, not an update
  # channel. Keep the value from the original NixOS installation forever.
  # 26.05 is correct only for a machine first installed with NixOS 26.05.
  # PLACEHOLDER: replace it if Helix was installed with another release.
  system.stateVersion = "26.05";
}
