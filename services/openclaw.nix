{ pkgs, ... }:

let
  stateDirectory = "/home/tristan/.local/state/openclaw";
  workspaceDirectory = "${stateDirectory}/workspace";
  repositoryDirectory = "/home/tristan/Projects/nixos-helix";
  emulationDirectory = "/mnt/games_nvme/emulation";
  secretFile = "/home/tristan/.config/openclaw/gateway.env";

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
      # The service sandbox below is the filesystem boundary: only OpenClaw's
      # state, the Helix repository, and the SSD emulation tree are writable.
      # The NAS is independently mounted read-only and reinforced here with a
      # read-only systemd path. This lets the agent inspect real machine state
      # and edit the declarative configuration without granting host-wide
      # writes.
      fs.workspaceOnly = false;
      exec = {
        security = "allowlist";
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

    unitConfig.ConditionUser = "tristan";

    environment = {
      HOME = "/home/tristan";
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

      BindPaths = [
        stateDirectory
        repositoryDirectory
        emulationDirectory
      ];
      ReadOnlyPaths = [ "-/mnt/infernalnexus" ];
      InaccessiblePaths = [
        "-/etc/nixos/secrets"
        "-/run/docker.sock"
        "-/var/run/docker.sock"
      ];
      IPAddressDeny = "any";
      IPAddressAllow = "localhost";
    };
  };
}
