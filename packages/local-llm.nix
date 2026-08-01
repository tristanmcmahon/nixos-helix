{ pkgs, ... }:

{
  # Use the NVIDIA-enabled Ollama build instead of installing competing local
  # inference runtimes.
  environment.systemPackages = [ pkgs.ollama-cuda ];
}
