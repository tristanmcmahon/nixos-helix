let
  pkgs = import <nixpkgs> { };
in
pkgs.mkShell {
  packages = with pkgs; [
    git
    # The reinstall restore test generates throwaway SSH host keys.
    openssh
    python3
    time
    nixfmt
    shellcheck
    deadnix
    statix
  ];
}
