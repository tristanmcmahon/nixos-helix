# The pinned Nixpkgs source for Helix. nixpkgs.json names an immutable NixOS
# release tarball and its hash, so a commit fully determines the system that
# CI, rebuilds and helix-update evaluate. Change it with scripts/bump-nixpkgs.sh.
let
  pin = builtins.fromJSON (builtins.readFile ./nixpkgs.json);
in
builtins.fetchTarball {
  name = "source";
  inherit (pin) url sha256;
}
