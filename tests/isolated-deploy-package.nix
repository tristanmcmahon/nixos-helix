# Build only the small installed deploy wrapper, never the system closure.
let
  system = import <nixpkgs/nixos> { configuration = ../configuration.nix; };
  packages = builtins.filter (
    package: (package.pname or package.name or "") == "helix-deploy-isolated"
  ) system.config.environment.systemPackages;
in
assert builtins.length packages == 1;
builtins.head packages
