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
        };

        db = {
          db = "ram";
          retention = 3600;
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

    # Keep a real /etc/netdata/stream.conf target in the declarative tree, then
    # overlay it inside Netdata's private service mount namespace with a runtime
    # file generated from mutable root-only state. The API UUID never enters the
    # Nix store.
    environment.etc."netdata/stream.conf".text = ''
      [stream]
          enabled = no
    '';

    systemd.services.netdata-stream-config = {
      description = "Render Helix Netdata parent stream configuration";
      before = [ "netdata.service" ];
      requiredBy = [ "netdata.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
      script = ''
                key_file=${lib.escapeShellArg streamKeyFile}
                output=/run/netdata-stream.conf

                if [[ -s "$key_file" ]]; then
                  key=$(tr -d '\r\n' < "$key_file")
                  if [[ ! "$key" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
                    echo "Netdata parent stream key is malformed: $key_file" >&2
                    exit 1
                  fi

                  umask 077
                  cat > "$output" <<EOF
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
                  umask 077
                  cat > "$output" <<'EOF'
        [stream]
            enabled = no
        EOF
                fi
      '';
    };

    systemd.services.netdata = {
      requires = lib.mkAfter [ "netdata-stream-config.service" ];
      after = lib.mkAfter [ "netdata-stream-config.service" ];
      path = lib.mkAfter [
        config.hardware.nvidia.package
        pkgs.smartmontools
      ];
      serviceConfig.BindReadOnlyPaths = [ "/run/netdata-stream.conf:/etc/netdata/stream.conf" ];
    };

    users.users.netdata.extraGroups = lib.mkAfter [
      "video"
      "render"
    ];
  };
}
