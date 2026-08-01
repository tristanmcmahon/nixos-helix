{ pkgs, ... }:

{
  # The service profile selects this same CUDA build. Keeping it in the system
  # path exposes the CLI to users; Nix deduplicates the shared store closure.
  environment.systemPackages = [ pkgs.ollama-cuda ];
}
