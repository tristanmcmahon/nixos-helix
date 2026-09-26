{
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../configuration.nix ];

  # CI validates the complete system integration without spending its entire
  # time allowance compiling heavyweight accelerator/emulation payloads. The
  # canonical configuration still selects ollama-cuda and enables hamCade;
  # these overrides exist only for the disposable release closure built by
  # scripts/check.sh. Canonical feature enablement is covered by evaluation
  # invariants and the dedicated emulation CI.
  services.ollama.package = lib.mkForce pkgs.ollama-cpu;
  helix.hamCade.enable = lib.mkForce false;
}
