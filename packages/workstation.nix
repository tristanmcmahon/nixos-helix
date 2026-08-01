{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vscode
    gh
    git-lfs
    ghostty

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
