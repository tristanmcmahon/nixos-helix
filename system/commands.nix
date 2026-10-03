{
  config,
  lib,
  pkgs,
  ...
}:

let
  health = config.helix.health;
  helixHealth = pkgs.writeShellApplication {
    name = "helix-health";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      gawk
      nix
      procps
      systemd
      util-linux
      openclaw
    ];
    # Each feature registers its own units, so disabling a feature also drops
    # it from the health gate.
    text = ''
      critical_units=(${lib.escapeShellArgs health.criticalUnits})
      critical_user_units=(${lib.escapeShellArgs health.criticalUserUnits})
    ''
    + builtins.readFile ../scripts/helix-health.sh;
  };
  helixUpdate = pkgs.writeShellApplication {
    name = "helix-update";
    runtimeInputs = with pkgs; [
      coreutils
      deadnix
      gawk
      git
      nix
      nix-output-monitor
      nixfmt
      nvd
      shellcheck
      statix
    ];
    text = ''
      helix_checkout=${lib.escapeShellArg (import ../config/helix.nix).checkout}
    ''
    + builtins.readFile ../scripts/helix-update.sh;
  };
in
{
  options.helix.health = {
    criticalUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "System units that helix-health --check requires to be active.";
    };
    criticalUserUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "User units that helix-health --check requires in a user session.";
    };
  };

  config.environment.systemPackages = [
    helixHealth
    helixUpdate
  ];
}
