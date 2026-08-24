{ config, ... }:

let
  release = import ./release.nix;
in
{
  # The root assembles ownership boundaries rather than implementation files.
  # Each default.nix below is the public entrypoint for one Helix layer.
  imports = [
    # Generated machine facts remain separate from maintained hardware policy.
    ./hardware-configuration.nix
    ./hardware/default.nix
    ./desktop/default.nix
    ./shell/default.nix
    ./system/default.nix
    ./services/default.nix
    ./profiles/default.nix
    ./packages/default.nix
  ];

  helix.emulation.enable = true;

  # NVIDIA, Chrome, ChatGPT and other selected workstation packages are not all
  # free software, so evaluation must permit unfree packages globally.
  nixpkgs.config.allowUnfree = true;

  # This is the compatibility floor from Helix's 26.05 fresh installation,
  # not the currently selected channel. Keep it unchanged across upgrades.
  system.stateVersion = release.stateVersion;

  assertions = [
    {
      assertion = config.system.nixos.release == release.nixosRelease;
      message = ''
        Helix requires NixOS ${release.nixosRelease}.
        The selected Nixpkgs reports NixOS ${config.system.nixos.release}.
      '';
    }
  ];
}
