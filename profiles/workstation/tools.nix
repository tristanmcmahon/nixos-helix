{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkIf config.helix.workstation.enable {
  environment.systemPackages = with pkgs; [
    ghostty
    openclaw

    unzip
    zip
    rsync

    ripgrep
    fd
    bat
    eza
    jq
    yq-go
    # One CPU/process monitor; nvtop covers the GPU (hardware-tools.nix).
    bottom
    fastfetch

    # Native Wayland clipboard tools. Keep macOS-compatible command names
    # below for muscle memory and scripts that already use pbcopy/pbpaste.
    wl-clipboard
  ];

  environment.shellAliases = {
    pbcopy = "wl-copy";
    pbpaste = "wl-paste";
  };
}
