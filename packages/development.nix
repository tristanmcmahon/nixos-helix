{ pkgs, ... }:

let
  vscodePinned = pkgs.callPackage ./vscode-pinned.nix { };
in
{
  environment.systemPackages = with pkgs; [
    vscodePinned
    helix
    gh
    git-lfs
    codex

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
