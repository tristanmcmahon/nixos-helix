context:
let
  inherit (context) config lib;
in
assert builtins.elem "nct6775" config.boot.kernelModules;
assert config.helix.monitoring.enable;
assert config.helix.monitoring.retentionTime == "400d";
assert config.helix.monitoring.scrapeInterval == "15s";
assert config.services.prometheus.enable;
assert config.services.prometheus.listenAddress == "127.0.0.1";
assert config.services.prometheus.retentionTime == "400d";
assert config.services.prometheus.exporters.node.enable;
assert config.services.prometheus.exporters.node.listenAddress == "127.0.0.1";
assert builtins.elem "systemd" config.services.prometheus.exporters.node.enabledCollectors;
assert config.services.prometheus.exporters.nvidia-gpu.enable;
assert config.services.prometheus.exporters.nvidia-gpu.listenAddress == "127.0.0.1";
assert config.services.prometheus.exporters.smartctl.enable;
assert config.services.prometheus.exporters.smartctl.listenAddress == "127.0.0.1";
assert config.services.prometheus.exporters.smartctl.maxInterval == "2m";
assert config.services.netdata.enable;
assert config.environment.etc."netdata/conf.d/stream.conf".text != "";
assert builtins.elem "/run/netdata-stream.conf:/etc/netdata/conf.d/stream.conf"
  config.systemd.services.netdata.serviceConfig.BindReadOnlyPaths;
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
assert builtins.elem "/run/netdata-stream.conf:/etc/netdata/stream.conf"
  config.systemd.services.netdata.serviceConfig.BindReadOnlyPaths;
assert !(builtins.elem 19999 config.networking.firewall.allowedTCPPorts);
assert config.services.grafana.enable;
assert config.services.grafana.settings.server.http_addr == "127.0.0.1";
assert config.services.grafana.settings.server.http_port == 3000;
assert config.services.grafana.settings."auth.anonymous".org_role == "Viewer";
assert config.services.grafana.settings.auth.disable_login_form;
assert lib.hasPrefix "$__file{" config.services.grafana.settings.security.secret_key;
assert config.programs.coolercontrol.enable;
assert !(builtins.elem 3000 config.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 9090 config.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 9100 config.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 9633 config.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 9835 config.networking.firewall.allowedTCPPorts);
true
