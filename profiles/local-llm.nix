{
  lib,
  pkgs,
  ...
}:

let
  modelProfiles = [
    {
      name = "helix-gemma";
      source = "gemma4:12b";
      context = 8192;
    }
    {
      name = "helix-gpt-oss";
      source = "gpt-oss:20b";
      context = 8192;
    }
    {
      name = "helix-qwen";
      source = "qwen3.6:27b";
      context = 4096;
    }
    {
      name = "helix-embedding";
      source = "qwen3-embedding:4b";
      context = 4096;
    }
  ];
  desiredModels = map (profile: profile.source) modelProfiles;
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
  status = pkgs.writeShellApplication {
    name = "helix-ollama-status";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.ollama-cuda
      pkgs.systemd
    ];
    text = ''
      case ''${1:-} in
      "") ;;
      --help)
        printf 'Usage: helix-ollama-status\n'
        printf 'Print the Ollama service, GPU, model, residency, and storage status.\n'
        exit 0
        ;;
      *)
        printf 'Usage: helix-ollama-status\n' >&2
        exit 2
        ;;
      esac

      printf 'Ollama service: '
      systemctl is-active ollama.service || true

      printf '\nGPU:\n'
      if command -v nvidia-smi >/dev/null; then
        nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu \
          --format=csv,noheader
      else
        printf 'nvidia-smi unavailable\n'
      fi

      printf '\nInstalled models:\n'
      ollama list
      printf '\nLoaded models and residency:\n'
      ollama ps

      printf '\nModel store: /mnt/games_nvme/ollama/models\n'
      if ! du -sh /mnt/games_nvme/ollama/models 2>/dev/null; then
        printf 'Size is protected; use: sudo du -sh /mnt/games_nvme/ollama/models\n'
      fi
      df -h /mnt/games_nvme
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
    loadModels = desiredModels;
    syncModels = false;
    environmentVariables = {
      # One 8K GPT-OSS runner left only about 1.2 GiB free on the 16 GiB GPU.
      # Serial loading and requests avoid turning normal use into VRAM contention.
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_NUM_PARALLEL = "1";
    };
  };

  environment.systemPackages = [
    status
    updateModels
  ];

  environment.etc = lib.listToAttrs (
    map (profile: {
      name = "helix/ollama/${profile.name}.Modelfile";
      value.text = ''
        FROM ${profile.source}
        PARAMETER num_ctx ${toString profile.context}
      '';
    }) modelProfiles
  );

  systemd.services.ollama = {
    requires = [ "helix-ollama-model-storage.service" ];
    after = [ "helix-ollama-model-storage.service" ];
  };

  # Extend the native loader so aliases are created only after their upstream
  # models have been reconciled. This remains one finite oneshot, not a daemon.
  systemd.services.ollama-model-loader.script = lib.mkAfter (
    lib.concatMapStringsSep "\n" (profile: ''
      ${lib.getExe pkgs.ollama-cuda} create ${lib.escapeShellArg profile.name} \
        --file ${lib.escapeShellArg "/etc/helix/ollama/${profile.name}.Modelfile"}
    '') modelProfiles
  );
}
