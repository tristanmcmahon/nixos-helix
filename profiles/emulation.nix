{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.emulation;
  infernalnexus = import ../config/infernalnexus.nix;
  romRoot = infernalnexus.shares.roms.mountPoint;
  romSource = infernalnexus.shares.roms.source;
  emulationRoot = "/mnt/games_nvme/emulation";
  stateRoot = "${emulationRoot}/state";

  retroarch = pkgs.retroarch.withCores (
    cores: with cores; [
      bsnes
    ]
  );

  emulationTools = import ./emulation/tools.nix {
    inherit
      lib
      pkgs
      romRoot
      romSource
      emulationRoot
      stateRoot
      ;
  };
  inherit (emulationTools)
    requireNas
    discover
    prepare
    scrape
    status
    ;

  emulationLaunchers = import ./emulation/launchers.nix {
    inherit
      lib
      pkgs
      prepare
      retroarch
      emulationRoot
      stateRoot
      ;
  };
  inherit (emulationLaunchers)
    pcsx2Launcher
    rpcs3Launcher
    shadps4Launcher
    retroarchLauncher
    desktopItems
    ;
in
{
  imports = [ ./emulation/storage.nix ];

  options.helix.emulation.enable = lib.mkEnableOption "NAS-first emulator stack";

  config = lib.mkIf cfg.enable {
    systemd = {
      user.services.helix-emulation-prepare = {
        description = "Prepare NAS-backed emulation paths for Tristan";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session-pre.target" ];
        unitConfig.ConditionUser = "tristan";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${prepare}/bin/helix-emulation-prepare";
        };
      };
    };

    environment.systemPackages = [
      pkgs.skyscraper
      requireNas
      discover
      prepare
      scrape
      status
      pcsx2Launcher
      rpcs3Launcher
      shadps4Launcher
      retroarchLauncher
    ]
    ++ desktopItems;

    # These applications use Vulkan/OpenGL and benefit from the same graphics
    # support as the normal gaming profile.
    hardware.graphics.enable32Bit = true;
    services.pipewire.alsa.support32Bit = true;

    assertions = [
      {
        assertion = config.programs.steam.enable;
        message = "helix.emulation requires the normal gaming profile so controller udev rules are present.";
      }
    ];
  };
}
