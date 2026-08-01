{ pkgs, ... }:

{
  imports = [ ../packages/local-llm.nix ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;

    # Binding explicitly to loopback prevents model access from the LAN without
    # relying on firewall policy alone.
    host = "127.0.0.1";
    openFirewall = false;
  };
}
