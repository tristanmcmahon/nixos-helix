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
  ];
}
