{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.monitoring;
  dashboard = ../config/monitoring/helix-overview.json;
  grafanaSecretFile = "${config.services.grafana.dataDir}/secret_key";
  grafanaUrl = "http://localhost:${toString cfg.grafanaPort}/d/helix-overview";

  monitorCommand = pkgs.writeShellApplication {
    name = "helix-monitor";
    runtimeInputs = [
      pkgs.coolercontrol.coolercontrol-gui
      pkgs.systemd
      pkgs.xdg-utils
    ];
    text = ''
      case ''${1:-dashboard} in
      dashboard)
        exec xdg-open ${lib.escapeShellArg grafanaUrl}
        ;;
      fans)
        exec coolercontrol
        ;;
      status)
        exec systemctl --no-pager --full status \
          grafana.service \
          prometheus.service \
          prometheus-node-exporter.service \
          prometheus-nvidia-gpu-exporter.service \
          prometheus-smartctl-exporter.service \
          coolercontrold.service
        ;;
      --help|-h)
        printf 'Usage: helix-monitor [dashboard|fans|status]\n'
        ;;
      *)
        printf 'Usage: helix-monitor [dashboard|fans|status]\n' >&2
        exit 2
        ;;
      esac
    '';
  };

  monitorLauncher = pkgs.makeDesktopItem {
    name = "helix-monitor";
    desktopName = "Helix Monitor";
    genericName = "Hardware history and health";
    comment = "Open Helix's local hardware dashboard";
    exec = "${monitorCommand}/bin/helix-monitor dashboard";
    icon = "utilities-system-monitor";
    categories = [
      "System"
      "Monitor"
    ];
    keywords = [
      "temperature"
      "fan"
      "gpu"
      "history"
    ];
  };
in
{
  options.helix.monitoring = {
    enable = lib.mkEnableOption "Helix local hardware monitoring and cooling controls";

    retentionTime = lib.mkOption {
      type = lib.types.str;
      default = "400d";
      description = "Prometheus sample retention period for Helix hardware history.";
    };

    scrapeInterval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      description = "Collection interval for local Helix hardware metrics.";
    };

    grafanaPort = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Local-only Grafana dashboard port.";
    };
  };

  config = lib.mkIf cfg.enable {
    # CoolerControl owns interactive fan curves and their mutable device-level
    # configuration. The repository enables it, but does not guess channel
    # names, safe PWM floors, or curves before physical validation on Helix.
    programs.coolercontrol.enable = true;

    services.prometheus = {
      enable = true;
      listenAddress = "127.0.0.1";
      port = 9090;
      inherit (cfg) retentionTime;
      globalConfig = {
        scrape_interval = cfg.scrapeInterval;
        evaluation_interval = "30s";
      };

      exporters = {
        node = {
          enable = true;
          listenAddress = "127.0.0.1";
          enabledCollectors = [ "systemd" ];
        };
        nvidia-gpu = {
          enable = true;
          listenAddress = "127.0.0.1";
        };
        smartctl = {
          enable = true;
          listenAddress = "127.0.0.1";
          maxInterval = "2m";
        };
      };

      scrapeConfigs = [
        {
          job_name = "helix-system";
          static_configs = [
            {
              targets = [ "127.0.0.1:9100" ];
              labels.instance = "helix";
            }
          ];
        }
        {
          job_name = "helix-nvidia";
          static_configs = [
            {
              targets = [ "127.0.0.1:9835" ];
              labels.instance = "helix";
            }
          ];
        }
        {
          job_name = "helix-storage-health";
          scrape_interval = "2m";
          static_configs = [
            {
              targets = [ "127.0.0.1:9633" ];
              labels.instance = "helix";
            }
          ];
        }
      ];
    };

    services.grafana = {
      enable = true;
      openFirewall = false;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cfg.grafanaPort;
          domain = "localhost";
          enable_gzip = true;
        };
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
          check_for_plugin_updates = false;
          feedback_links_enabled = false;
        };
        users.allow_sign_up = false;
        auth.disable_login_form = true;
        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
          hide_version = true;
        };
        security = {
          disable_gravatar = true;
          cookie_samesite = "strict";
          secret_key = "$__file{${grafanaSecretFile}}";
        };
        dashboards.default_home_dashboard_path =
          "/etc/helix/monitoring/dashboards/helix-overview.json";
      };

      provision = {
        enable = true;
        datasources.settings = {
          apiVersion = 1;
          prune = true;
          datasources = [
            {
              name = "Helix history";
              uid = "helix-prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://127.0.0.1:9090";
              isDefault = true;
              editable = false;
              jsonData = {
                httpMethod = "POST";
                timeInterval = cfg.scrapeInterval;
              };
            }
          ];
        };
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "Helix";
              orgId = 1;
              folder = "";
              type = "file";
              disableDeletion = true;
              editable = false;
              options.path = "/etc/helix/monitoring/dashboards";
            }
          ];
        };
      };
    };

    environment.etc."helix/monitoring/dashboards/helix-overview.json".source = dashboard;
    environment.systemPackages = [
      monitorCommand
      monitorLauncher
    ];

    # Grafana 12 requires a stable database-encryption key. Generate it once
    # inside Grafana's private state directory instead of exposing it through
    # the world-readable Nix store.
    systemd.services.grafana.preStart = lib.mkBefore ''
      if [[ ! -s ${lib.escapeShellArg grafanaSecretFile} ]]; then
        umask 077
        ${pkgs.openssl}/bin/openssl rand -hex 32 > ${lib.escapeShellArg grafanaSecretFile}
      fi
    '';
  };
}
