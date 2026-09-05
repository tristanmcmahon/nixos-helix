{ pkgs, ... }:

{
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
    htop
    btop
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
