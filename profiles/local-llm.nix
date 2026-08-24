{
  lib,
  pkgs,
  ...
}:

let
  desiredModels = [
    "deepseek-r1:8b"
    "gemma4:12b"
    "gpt-oss:20b"
    "qwen3.6:27b"
    "qwen3-embedding:4b"
  ];
  updateModels = pkgs.writeShellApplication {
    name = "helix-ollama-update-models";
    runtimeInputs = [ pkgs.ollama-cuda ];
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
  imports = [ ../packages/local-llm.nix ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    user = "ollama";
    group = "ollama";
    models = "/mnt/games_nvme/ollama/models";

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

  environment.systemPackages = [ updateModels ];

  systemd.services.ollama = {
    requires = [ "helix-ollama-model-storage.service" ];
    after = [ "helix-ollama-model-storage.service" ];
  };
}
