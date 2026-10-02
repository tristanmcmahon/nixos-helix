{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.monitoring;
  # History lives on the Netdata parent on Infernalnexus (services/netdata.nix
  # streams to it). Helix keeps only live cooling control.
  netdataUrl = "http://${(import ../config/infernalnexus.nix).host}:19999/";

  fanCommissionCommand = pkgs.writeShellApplication {
    name = "helix-fan-commission";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${../scripts/helix-fan-commission.py} "$@"
    '';
  };

  monitorCommand = pkgs.writeShellApplication {
    name = "helix-monitor";
    runtimeInputs = [
      pkgs.coolercontrol.coolercontrol-gui
      pkgs.systemd
      pkgs.xdg-utils
      fanCommissionCommand
    ];
    text = ''
      case ''${1:-netdata} in
      netdata)
        exec xdg-open ${lib.escapeShellArg netdataUrl}
        ;;
      fans)
        exec coolercontrol
        ;;
      commission)
        exec helix-fan-commission commission --apply
        ;;
      inventory)
        exec helix-fan-commission inventory
        ;;
      restore)
        exec helix-fan-commission restore
        ;;
      status)
        exec systemctl --no-pager --full status coolercontrold.service netdata.service
        ;;
      --help|-h)
        printf 'Usage: helix-monitor [netdata|fans|commission|inventory|restore|status]\n'
        ;;
      *)
        printf 'Usage: helix-monitor [netdata|fans|commission|inventory|restore|status]\n' >&2
        exit 2
        ;;
      esac
    '';
  };

  monitorLauncher = pkgs.makeDesktopItem {
    name = "helix-monitor";
    desktopName = "Helix Monitor";
    genericName = "Workstation and NAS monitoring";
    comment = "Open the Netdata parent on Infernalnexus, which keeps Helix's history";
    exec = "${monitorCommand}/bin/helix-monitor netdata";
    icon = "utilities-system-monitor";
    categories = [
      "System"
      "Monitor"
    ];
    keywords = [
      "netdata"
      "temperature"
      "fan"
      "gpu"
      "nas"
    ];
  };
in
{
  options.helix.monitoring.enable = lib.mkEnableOption "Helix's Netdata stream to Infernalnexus and cooling controls";

  config = lib.mkIf cfg.enable {
    helix.health.criticalUnits = [ "coolercontrold.service" ];

    # This exact ASUS board is supported by nct6775 through WMBD. The device is
    # not PCI-discoverable, so explicitly load the module for motherboard
    # temperatures, fan RPM, and PWM channels.
    boot.kernelModules = [ "nct6775" ];

    # CoolerControl owns the mutable device-level settings. The repository's
    # guarded commissioner discovers usable channels, measures conservative
    # floors, and creates profiles through CoolerControl's local API.
    programs.coolercontrol.enable = true;

    environment.systemPackages = [
      fanCommissionCommand
      monitorCommand
      monitorLauncher
    ];
  };
}
