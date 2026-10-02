{
  config,
  lib,
  pkgs,
  ...
}:

let
  helix = import ../config/helix.nix;
  cfg = config.helix.emulation;
  infernalnexus = import ../config/infernalnexus.nix;
  romRoot = infernalnexus.shares.roms.mountPoint;
  romSource = infernalnexus.shares.roms.source;
  emulationRoot = "${helix.gamesNvme.mountPoint}/emulation";
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

  options.helix.emulation.enable = lib.mkEnableOption "NAS-first console emulator stack";

  config = lib.mkIf cfg.enable {
    systemd = {
      user.services.helix-emulation-prepare = {
        description = "Prepare NAS-backed emulation paths for Tristan";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session-pre.target" ];
        unitConfig.ConditionUser = helix.user;
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

    # The gaming profile supplies 32-bit graphics and audio, which these
    # Vulkan/OpenGL emulators also use, and Steam's controller udev rules.
    assertions = [
      {
        assertion = config.programs.steam.enable && config.hardware.graphics.enable32Bit;
        message = "helix.emulation requires helix.gaming (Steam controller udev rules and 32-bit graphics).";
      }
    ];
  };
}
