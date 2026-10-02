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
    "grafana.service"
    "prometheus.service"
    "netdata.service"
    "coolercontrold.service"
  ]);
assert !config.services.prometheus.enable;
assert !config.services.prometheus.exporters.node.enable;
assert !config.services.prometheus.exporters.nvidia-gpu.enable;
assert !config.services.prometheus.exporters.smartctl.enable;
assert !config.services.grafana.enable;
assert !config.programs.coolercontrol.enable;
assert !(builtins.elem "nct6775" config.boot.kernelModules);
assert !(builtins.hasAttr "helix/monitoring/dashboards/helix-overview.json" config.environment.etc);
assert !(builtins.elem "helix-monitor" packageNames);
assert !(builtins.elem "helix-fan-commission" packageNames);
true
