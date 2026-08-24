{ ... }:

{
  # Cross-cutting machine services live here. Feature-specific lifecycle is
  # imported by the profile that owns the feature.
  imports = [
    ./maintenance.nix
    ./openssh.nix
  ];
}
