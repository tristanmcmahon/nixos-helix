{ pkgs, ... }:

let
  nixpkgsRev = "0e251e24a4f24e036a084b6b4b2d2491af4167f4";
  nixpkgsSrc = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/${nixpkgsRev}.tar.gz";
    sha256 = "118n3xlp9fyf52588yhxa0a5xyi0gchci09l0vblrm7m8zimvln8";
  };
  pinnedPkgs = import nixpkgsSrc {
    inherit (pkgs) config;
    overlays = [ ];
  };
  pinnedVersion = pinnedPkgs.vscode.version;
in
assert pinnedVersion == "1.132.0";
pinnedPkgs.vscode
