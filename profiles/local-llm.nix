{ pkgs, ... }:

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
  };

  systemd.services.ollama = {
    requires = [ "helix-ollama-model-storage.service" ];
    after = [ "helix-ollama-model-storage.service" ];
  };
}
