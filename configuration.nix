{
  config,
  lib,
  pkgs,
  ...
}:

let
  release = import ./release.nix;
  infernalnexus = import ./config/infernalnexus.nix;
in
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
    ./hardware/controllers.nix
    ./hardware/firmware.nix
    ./hardware/corsair-k70.nix

    ./desktop/plasma.nix
    ./desktop/hyprland.nix
    ./desktop/applications.nix
    ./desktop/fonts.nix
    ./desktop/ghostty.nix
    ./desktop/browsers.nix
    ./desktop/onepassword.nix
    ./desktop/theme.nix

    ./shell/modern-bash.nix
    ./shell/git.nix

    ./system/boot.nix
    ./system/hosts.nix
    ./system/networking.nix
    ./system/nas.nix
    ./system/storage.nix
    ./system/users.nix
    ./system/locale.nix
    ./system/memory-pressure.nix
    ./system/commands.nix
    ./services/maintenance.nix
    ./services/backup.nix
    ./services/monitoring.nix
    ./services/netdata.nix
    ./services/hamsteam.nix
    ./services/hamology-backup.nix
    ./services/failure-alerts.nix
    ./services/openclaw.nix
    ./services/openssh.nix

    # Feature profiles. Each declares a helix.<feature>.enable option; the
    # choices below, not this import list, decide what Helix includes.
    ./profiles/workstation.nix
    ./profiles/development.nix
    ./profiles/gaming.nix
    ./profiles/hamcade.nix
    ./profiles/emulation.nix
    ./profiles/local-llm.nix

    # The deliberately small package set needed on every Helix installation.
    ./packages/base.nix
    ./packages/openclaw.nix
  ];

  helix = {
    workstation.enable = true;
    development.enable = true;
    gaming.enable = true;
    localLlm.enable = true;
    emulation.enable = true;
    hamCade.enable = true;
    monitoring.enable = true;

    # Helix is the first client of the Pi-hole on infernalnexus. This is a
    # workstation-local DNS policy only; it does not alter router or LAN DNS.
    networking.pihole = {
      enable = true;
      address = infernalnexus.host;
    };
  };

  # Unfree software is allowed by name, so each new unfree package is a
  # deliberate choice: evaluation refuses anything not listed here.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    let
      names = [
        (lib.getName pkg)
        (builtins.parseDrvName (pkg.name or "")).name
      ];
      allowed = [
        # NVIDIA driver and settings (hardware/nvidia.nix)
        "nvidia-x11"
        "nvidia-settings"
        # Desktop applications
        "1password"
        "1password-cli"
        "google-chrome"
        "obsidian"
        "plex-desktop"
        "spotify"
        "vscode"
        "claude-code"
        # Gaming and emulation
        "steam"
        "steam-unwrapped"
        "rpcs3"
        # Netdata's bundled dashboard
        "netdata"
      ];
      # CUDA, for the CUDA build of Ollama (profiles/local-llm.nix); its
      # library names carry the CUDA version, so allow the family.
      isCuda = name: name == "cuda-merged" || builtins.match "cuda[0-9.]+-.*" name != null;
    in
    builtins.any (name: builtins.elem name allowed || isCuda name) names;

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
    {
      assertion = builtins.compareVersions pkgs.openclaw.version "2026.6.9" >= 0;
      message = "Helix requires the reviewed stable OpenClaw pin at 2026.6.9 or newer.";
    }
  ];
}
