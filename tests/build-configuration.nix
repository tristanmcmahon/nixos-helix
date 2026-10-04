{
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../configuration.nix ];

  # The --full gate validates the complete system integration without
  # compiling heavyweight accelerator/emulation payloads (CUDA, MAME). The
  # canonical configuration still selects ollama-cuda and enables hamCade;
  # these overrides exist only for the disposable release closure built by
  # scripts/check.sh. Inspected desktop, session and 1Password artifacts come
  # from the canonical configuration (tests/artifacts.nix), so keep these
  # overrides to heavy payloads. Canonical feature enablement is covered by evaluation
  # invariants and the dedicated emulation CI.
  services.ollama.package = lib.mkForce pkgs.ollama-cpu;
  helix.hamCade.enable = lib.mkForce false;
  helix.emulation.enable = lib.mkForce false;
}
