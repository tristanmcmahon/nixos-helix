{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vscode
    helix
    gh
    git-lfs
    codex

    bottom
    ripgrep
    fd
    bat
    fzf
    dust

    gcc
    gnumake
    pkg-config
    python3
    # The Nixpkgs Node.js package includes npm.
    nodejs
    nil
    nixfmt
    shellcheck
  ];
}
