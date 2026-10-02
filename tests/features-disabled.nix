# Every optional Helix feature can be disabled together, and disabling one
# removes its packages, services and storage initialisers.
let
  system = import <nixpkgs/nixos> {
    configuration =
      { lib, ... }:
      {
        imports = [ ../configuration.nix ];
        helix = lib.mapAttrs (_: _: { enable = lib.mkForce false; }) {
          workstation = null;
          development = null;
          gaming = null;
          localLlm = null;
          emulation = null;
          hamCade = null;
          monitoring = null;
        };
      };
  };
  inherit (system) config;
  packageNames = map (package: package.pname or package.name or "") config.environment.systemPackages;
  absent = name: !(builtins.elem name packageNames);
in
# The system still evaluates completely, including its assertions.
assert builtins.isString config.system.build.toplevel.drvPath;
# workstation
assert absent "bottom" && absent "ripgrep" && absent "spotify";
# development
assert absent "claude-code" && absent "codex" && absent "vscode" && absent "gcc-wrapper";
# gaming
assert !config.programs.steam.enable && !config.hardware.graphics.enable32Bit;
assert !(config.systemd.services ? helix-doom-storage) && absent "gzdoom";
# local LLM
assert !config.services.ollama.enable && !(config.systemd.services ? helix-ollama-model-storage);
# emulation
assert !(config.systemd.services ? helix-emulation-storage);
# Only the always-on units remain in the health gate.
assert config.helix.health.criticalUnits == [ "sshd.service" ];
# The recovery base survives with every feature disabled.
assert builtins.all (name: builtins.elem name packageNames) [
  "git"
  "vim"
  "curl"
];
true
