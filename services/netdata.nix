{
  config,
  lib,
  pkgs,
  ...
}:

let
  infernalnexus = import ../config/infernalnexus.nix;
  parentAddress = infernalnexus.host;
  streamKeyFile = "/var/lib/netdata/parent-api-key";

  nvidiaCollector = pkgs.writeText "netdata-nvidia-smi.conf" ''
    update_every: 5
    autodetection_retry: 30

    jobs:
      - name: helix-gpu
        binary_path: ${config.hardware.nvidia.package}/bin/nvidia-smi
        loop_mode: yes
        timeout: 10
  '';

  smartCollector = pkgs.writeText "netdata-smartctl.conf" ''
    update_every: 10

    jobs:
      - name: helix-storage
        poll_devices_every: 60
  '';

  systemdCollector = pkgs.writeText "netdata-systemdunits.conf" ''
    update_every: 5

    jobs:
      - name: services
        include:
          - '*.service'
        collect_unit_files: true
        collect_unit_files_every: 300
  '';
in
{
  config = lib.mkIf config.helix.monitoring.enable {
    services.netdata = {
      enable = true;
      package = pkgs.netdata.override {
        withCloudUi = true;
        withNdsudo = true;
      };
      enableAnalyticsReporting = false;

      config = {
        global = {
          hostname = "helix";
          "update every" = 5;
          "config directory" = "/run/netdata/conf.d";
        };

        db = {
          db = "ram";
          retention = "1h";
        };

        web = {
          "default port" = 19999;
          "bind to" = "127.0.0.1:19999";
          "allow connections from" = "localhost";
          "allow dashboard from" = "localhost";
          "allow streaming from" = "localhost";
          "allow management from" = "localhost";
          "allow netdata.conf from" = "localhost";
          "allow mcp from" = "localhost";
        };

        "host labels" = {
          role = "workstation";
          site = "home";
          gpu = "rtx-5080";
          owner = "nixos-helix";
        };
      };

      configDir = {
        "go.d/nvidia_smi.conf" = nvidiaCollector;
        "go.d/smartctl.conf" = smartCollector;
        "go.d/systemdunits.conf" = systemdCollector;
      };

      extraNdsudoPackages = [ pkgs.smartmontools ];
    };

    # The streaming UUID is deliberately mutable state rather than Nix-store
    # configuration. Before the pairing tool installs it, Netdata still runs as
    # a useful loopback-only local agent with outbound streaming disabled.
    systemd.services.netdata.preStart = lib.mkBefore ''
            runtime_config=/run/netdata/conf.d
            static_config=/etc/netdata/conf.d
            key_file=${lib.escapeShellArg streamKeyFile}

            rm -rf "$runtime_config"
            install -d -m 0750 "$runtime_config"

            if [[ -d "$static_config/go.d" ]]; then
              ln -s "$static_config/go.d" "$runtime_config/go.d"
            fi

            if [[ -s "$key_file" ]]; then
              key=$(tr -d '\r\n' < "$key_file")
              if [[ ! "$key" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
                echo "Netdata parent stream key is malformed: $key_file" >&2
                exit 1
              fi

              cat > "$runtime_config/stream.conf" <<EOF
      [stream]
          enabled = yes
          destination = ${parentAddress}:19999
          api key = $key
          enable compression = yes
          send charts matching = *
          buffer size bytes = 10485760
          reconnect delay = 5s
      EOF
            else
              cat > "$runtime_config/stream.conf" <<'EOF'
      [stream]
          enabled = no
      EOF
            fi

            chmod 0600 "$runtime_config/stream.conf"
    '';

    systemd.services.netdata.path = lib.mkAfter [
      config.hardware.nvidia.package
      pkgs.smartmontools
    ];

    users.users.netdata.extraGroups = lib.mkAfter [
      "video"
      "render"
    ];
  };
}
