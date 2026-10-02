let
  system = import <nixpkgs/nixos> {
    configuration =
      { lib, ... }:
      {
        imports = [ ../configuration.nix ];
        helix.monitoring.enable = lib.mkForce false;
      };
  };
  inherit (system) config;
  packageNames = map (package: package.pname or package.name or "") config.environment.systemPackages;
in
assert !config.helix.monitoring.enable;
# Disabling monitoring removes its units from the health gate.
assert
  !(builtins.any (unit: builtins.elem unit config.helix.health.criticalUnits) [
    "netdata.service"
    "coolercontrold.service"
  ]);
assert !config.programs.coolercontrol.enable;
assert !(builtins.elem "nct6775" config.boot.kernelModules);
assert !(builtins.elem "helix-monitor" packageNames);
assert !(builtins.elem "helix-fan-commission" packageNames);
true
