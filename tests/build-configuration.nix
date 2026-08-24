{
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../configuration.nix ];

  # General CI validates the system integration without rebuilding the two
  # expensive closures that have focused checks. The canonical configuration
  # still enables ollama-cuda and emulation; these overrides exist only for the
  # disposable closure built by scripts/check.sh.
  services.ollama.package = lib.mkForce pkgs.ollama-cpu;
  helix.emulation.enable = lib.mkForce false;
}
