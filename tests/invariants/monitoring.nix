context:
let
  inherit (context) config;
in
assert builtins.elem "nct6775" config.boot.kernelModules;
assert config.helix.monitoring.enable;
assert config.services.netdata.enable;
assert config.services.netdata.configDir."stream.conf" == "/run/netdata-stream.conf";
assert !config.services.netdata.enableAnalyticsReporting;
assert config.services.netdata.package.withNdsudo;
assert config.services.netdata.config.global.hostname == "helix";
assert config.services.netdata.config.db.db == "ram";
assert config.services.netdata.config.db.retention == 3600;
assert config.services.netdata.config.web."bind to" == "127.0.0.1:19999";
assert config.services.netdata.config.web."allow dashboard from" == "localhost";
assert config.services.netdata.config.web."allow management from" == "localhost";
assert config.services.netdata.config."host labels".role == "workstation";
assert builtins.hasAttr "go.d/nvidia_smi.conf" config.services.netdata.configDir;
assert builtins.hasAttr "go.d/smartctl.conf" config.services.netdata.configDir;
assert builtins.hasAttr "go.d/systemdunits.conf" config.services.netdata.configDir;
assert builtins.elem "netdata-stream-config.service" config.systemd.services.netdata.requires;
assert builtins.elem "netdata-stream-config.service" config.systemd.services.netdata.after;
assert !(builtins.elem 19999 config.networking.firewall.allowedTCPPorts);
assert config.programs.coolercontrol.enable;
# History lives on the Infernalnexus Netdata parent; the local Prometheus and
# Grafana stack was retired and must not return.
assert !config.services.prometheus.enable;
assert !config.services.prometheus.exporters.node.enable;
assert !config.services.prometheus.exporters.nvidia-gpu.enable;
assert !config.services.prometheus.exporters.smartctl.enable;
assert !config.services.grafana.enable;
true
