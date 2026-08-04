{ ... }:

{
  # A NixOS configuration is assembled by importing modules. Each module below
  # contributes option values to one combined system configuration; file order
  # does not imply service start order.
  imports = [
    # This is Helix's real generated hardware module. It owns filesystems,
    # boot-critical modules, the platform, and CPU microcode selection.
    ./hardware-configuration.nix

    ./hardware/nvidia.nix
    ./hardware/audio.nix
    ./hardware/bluetooth.nix
    ./hardware/firmware.nix
    ./hardware/corsair-k70.nix

    ./desktop/plasma.nix
    ./desktop/hyprland.nix
    ./desktop/applications.nix
    ./desktop/fonts.nix
    ./desktop/ghostty.nix
    ./desktop/onepassword.nix
    ./desktop/theme.nix

    ./shell/modern-bash.nix

    ./system/boot.nix
    ./system/hosts.nix
    ./system/networking.nix
    ./system/nas.nix
    ./system/users.nix
    ./system/locale.nix
    ./services/maintenance.nix
    ./services/openssh.nix

    # These profiles form the normal Plasma workstation. Gaming is active;
    # local inference remains opt-in because it adds substantial software and policy.
    ./profiles/workstation.nix
    ./profiles/development.nix
    ./profiles/gaming.nix
    # ./profiles/local-llm.nix

    # The deliberately small package set needed on every Helix installation.
    ./packages/base.nix
  ];

  # NVIDIA's user-space driver is redistributable but not free software, so
  # Nixpkgs will refuse to evaluate it unless unfree packages are permitted.
  # This does not install CUDA or any other compute/development stack.
  nixpkgs.config.allowUnfree = true;

  # This is the compatibility floor from Helix's original installation, not
  # the currently selected channel. Keep it unchanged across upgrades.
  system.stateVersion = "25.11";
}
