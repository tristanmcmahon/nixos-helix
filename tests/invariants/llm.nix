context:
let
  inherit (context) config lib system;
in
assert config.services.ollama.enable;
assert config.services.ollama.host == "127.0.0.1";
assert !config.services.ollama.openFirewall;
assert config.services.ollama.package == system.pkgs.ollama-cuda;
assert config.services.ollama.user == "ollama";
assert config.services.ollama.group == "ollama";
assert config.services.ollama.models == "/mnt/games_nvme/ollama/models";
assert
  config.services.ollama.loadModels == [
    "deepseek-r1:8b"
    "gemma4:12b"
    "gpt-oss:20b"
    "qwen3.6:27b"
    "qwen3-embedding:4b"
  ];
assert !config.services.ollama.syncModels;
assert builtins.hasAttr "ollama" config.systemd.services;
assert builtins.hasAttr "ollama-model-loader" config.systemd.services;
assert builtins.elem "ollama.service" config.systemd.services.ollama-model-loader.after;
assert builtins.elem "ollama.service" config.systemd.services.ollama-model-loader.bindsTo;
assert builtins.all (
  model: lib.hasInfix model config.systemd.services.ollama-model-loader.script
) config.services.ollama.loadModels;
assert builtins.elem "helix-ollama-model-storage.service" config.systemd.services.ollama.requires;
assert builtins.elem "helix-ollama-model-storage.service" config.systemd.services.ollama.after;
assert
  config.systemd.services.helix-ollama-model-storage.unitConfig.ConditionPathIsMountPoint
  == "/mnt/games_nvme";
true
