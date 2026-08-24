{
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../configuration.nix ];

  # CI validates the complete system integration without spending its entire
  # time allowance compiling llama.cpp's CUDA template matrix. The canonical
  # configuration still selects ollama-cuda; this override exists only for the
  # disposable closure built by scripts/check.sh.
  services.ollama.package = lib.mkForce pkgs.ollama-cpu;
}
