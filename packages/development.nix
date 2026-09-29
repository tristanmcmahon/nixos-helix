{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    vscode
    zed-editor
    helix
    gh
    git-lfs
    codex
    (callPackage ./hamllm.nix { })

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
