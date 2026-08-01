{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Helix remains available as the existing terminal editor. VS Code belongs
    # to the workstation package set rather than the compiler toolchain.
    helix

    gcc
    gnumake
    pkg-config
    python3
    # The Nixpkgs Node.js package includes npm.
    nodejs
    nil
    nixfmt-rfc-style
    shellcheck
  ];
}
