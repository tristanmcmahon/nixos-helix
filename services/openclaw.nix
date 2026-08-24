{ pkgs, ... }:

let
  host = import ../config/host.nix;
  stateDirectory = "${host.home}/.local/state/openclaw";
  workspaceDirectory = "${stateDirectory}/workspace";
  secretFile = "${host.home}/.config/openclaw/gateway.env";

  openclawConfig = (pkgs.formats.json { }).generate "openclaw.json" {
    gateway = {
      mode = "local";
      bind = "loopback";
      auth.mode = "token";
    };

    models = {
      mode = "replace";
      pricing.enabled = false;
      providers.ollama = {
        baseUrl = "http://127.0.0.1:11434";
        apiKey = "ollama-local";
        api = "ollama";
        timeoutSeconds = 300;
        contextWindow = 32768;
        contextTokens = 32768;
        models = [
          {
            id = "gpt-oss:20b";
            name = "gpt-oss:20b";
            reasoning = true;
            input = [ "text" ];
            contextWindow = 32768;
            contextTokens = 32768;
            params.num_ctx = 32768;
          }
        ];
      };
    };

    agents.defaults = {
      workspace = workspaceDirectory;
      model.primary = "ollama/gpt-oss:20b";
    };

    tools = {
      fs.workspaceOnly = true;
      exec = {
        security = "deny";
        ask = "always";
      };
      elevated.enabled = false;
    };
  };
in
{
  systemd.user.services.openclaw-gateway = {
    description = "OpenClaw local gateway";
    wantedBy = [ "default.target" ];
    after = [ "network.target" ];

    unitConfig.ConditionUser = host.user;

    environment = {
      HOME = host.home;
      OPENCLAW_CONFIG_PATH = openclawConfig;
      OPENCLAW_STATE_DIR = stateDirectory;
    };

    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${workspaceDirectory}";
      ExecStart = "${pkgs.openclaw}/bin/openclaw gateway run";
      EnvironmentFile = secretFile;
      Restart = "on-failure";
      RestartSec = "5s";

      StateDirectory = "openclaw";
      StateDirectoryMode = "0700";
      ConfigurationDirectory = "openclaw";
      ConfigurationDirectoryMode = "0700";

      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = "tmpfs";
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictSUIDSGID = true;

      BindPaths = [ stateDirectory ];
      BindReadOnlyPaths = [ secretFile ];
      InaccessiblePaths = [
        "-/run/docker.sock"
        "-/var/run/docker.sock"
      ];
      IPAddressDeny = "any";
      IPAddressAllow = "localhost";
    };
  };
}
