{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.hamCade;
  dependencies = import ../vendor/hamcade/dependencies.nix { inherit pkgs; };
  application = "/home/tristan/Projects/hamCade/hamcade.py";
  launcher = pkgs.writeShellApplication {
    name = "hamcade";
    runtimeInputs = [
      pkgs.python3
      pkgs.bubblewrap
      pkgs.util-linux
      pkgs.curl
      pkgs.kdePackages.kdialog
    ];
    text = ''
      if [[ ! -f ${lib.escapeShellArg application} ]]; then
        printf 'hamCade is not available at %s. Clone or restore ~/Projects/hamCade first.\n' \
          ${lib.escapeShellArg application} >&2
        exit 1
      fi
      exec python3 ${lib.escapeShellArg application} "$@"
    '';
  };
in
{
  options.helix.hamCade.enable = lib.mkEnableOption "hamCade arcade library";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      launcher
      dependencies.frontend
      dependencies.core
      dependencies.auditMame
      dependencies.retroarch
      dependencies.shaders
      dependencies.controllers
      dependencies.sevenzip
      dependencies.chdtools
      (pkgs.makeDesktopItem {
        name = "hamcade";
        desktopName = "hamCade";
        comment = "Arcade games from your read-only NAS library";
        exec = "hamcade launch";
        icon = "applications-games";
        categories = [ "Game" ];
      })
    ];
  };
}
