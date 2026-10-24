{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.benchmark;

  benchmarkCommand = pkgs.writeShellApplication {
    name = "helix-benchmark";
    runtimeInputs = [
      pkgs.procps
      pkgs.python3
      pkgs.sysbench
      pkgs.vkmark
    ];
    text = ''
      exec python3 ${../scripts/helix-benchmark.py} "$@"
    '';
  };
in
{
  options.helix.benchmark.enable = lib.mkEnableOption "lightweight system/compute/GPU/LLM self-benchmarking (helix-benchmark)";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      benchmarkCommand
      # Registers MangoHud's Vulkan overlay/logging layer system-wide so the
      # GPU benchmark's MANGOHUD=1 env var takes effect, independent of
      # whether helix.gaming also installs it.
      pkgs.mangohud
    ];
  };
}
