{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  helix = import ../config/helix.nix;
  helixLib = import ../lib/helix.nix { inherit lib pkgs utils; };
  cfg = config.helix.localLlm;
  modelStore = "${helix.gamesNvme.mountPoint}/ollama/models";
  desiredModels = [
    "deepseek-r1:8b"
    "gemma4:12b"
    "gpt-oss:20b"
    "qwen3.6:27b"
    "qwen3-embedding:4b"
  ];
  updateModels = pkgs.writeShellApplication {
    name = "helix-ollama-update-models";
    runtimeInputs = [ config.services.ollama.package ];
    text = ''
      if ! ollama list >/dev/null; then
        printf 'Ollama is unavailable at %s. Start the service before refreshing models.\n' \
          "''${OLLAMA_HOST:-http://127.0.0.1:11434}" >&2
        exit 1
      fi

      for model in ${lib.escapeShellArgs desiredModels}; do
        ollama pull "$model"
      done
    '';
  };
in
{
  options.helix.localLlm.enable = lib.mkEnableOption "local CUDA inference with Ollama";

  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = pkgs.ollama-cuda;
      user = "ollama";
      group = "ollama";
      models = modelStore;

      # Binding explicitly to loopback prevents model access from the LAN without
      # relying on firewall policy alone.
      host = "127.0.0.1";
      openFirewall = false;
      environmentVariables = {
        OLLAMA_CONTEXT_LENGTH = "32768";
      };
      loadModels = desiredModels;
      syncModels = false;
    };

    # The service's CUDA build doubles as the user-facing CLI; Nix deduplicates
    # the shared store closure.
    helix.health.criticalUnits = [ "ollama.service" ];

    environment.systemPackages = [
      config.services.ollama.package
      updateModels
    ];

    systemd.services = {
      ollama = {
        requires = [ "helix-ollama-model-storage.service" ];
        after = [ "helix-ollama-model-storage.service" ];
      };
      # The loader exits after pulling, so every activation used to start it
      # again and re-pull all declared tags. Staying active keeps it to once
      # per boot, and again whenever ollama.service restarts (it BindsTo it).
      ollama-model-loader.serviceConfig.RemainAfterExit = true;
      helix-ollama-model-storage = helixLib.mkMountedDirectory {
        description = "Create the Ollama model store on GAMES_NVME";
        inherit (helix.gamesNvme) mountPoint;
        path = modelStore;
        owner = "ollama";
        group = "ollama";
        mode = "0750";
      };
    };
  };
}
