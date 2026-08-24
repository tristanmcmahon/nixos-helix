{
  config,
  lib,
  pkgs,
  ...
}:

let
  host = import ../config/host.nix;
  cfg = config.helix.emulation;
  nasRoot = "/mnt/infernalnexus/nas1";
  nasSource = "//192.168.1.8/nas1";
  romRoot = "/mnt/infernalnexus/roms";
  romSource = "//192.168.1.8/roms";
  emulationRoot = "${nasRoot}/Emulation";
  arcadeRoot = "${emulationRoot}/roms/arcade";
  stateRoot = "${emulationRoot}/state";

  storage = import ./emulation/storage.nix {
    inherit
      emulationRoot
      lib
      nasRoot
      nasSource
      pkgs
      romRoot
      romSource
      stateRoot
      ;
  };
  metadata = import ./emulation/metadata.nix {
    inherit
      arcadeRoot
      emulationRoot
      lib
      pkgs
      romRoot
      ;
    inherit (storage) prepare requireNas;
  };
  launchers = import ./emulation/launchers.nix {
    inherit
      arcadeRoot
      emulationRoot
      lib
      nasRoot
      pkgs
      romRoot
      stateRoot
      ;
    inherit (storage) prepare;
  };

  inherit (storage) discover prepare requireNas;
  inherit (metadata) auditArcade datIndex scrape;
  inherit (launchers)
    desktopItems
    mameLauncher
    pcsx2Launcher
    retroarchLauncher
    rpcs3Launcher
    shadps4Launcher
    status
    ;
in
{
  options.helix.emulation.enable = lib.mkEnableOption "NAS-first emulator stack";

  config = lib.mkIf cfg.enable {
    # tfpga and Helix share one authoritative ROM collection. It is exposed
    # only while this module is enabled and is deliberately read-only here.
    system.fsPackages = [ pkgs.cifs-utils ];

    systemd = {
      mounts = [
        {
          description = "Infernalnexus authoritative ROM collection";
          what = romSource;
          where = romRoot;
          type = "cifs";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          options = builtins.concatStringsSep "," [
            "credentials=/etc/nixos/secrets/infernalnexus-smb"
            "uid=${host.user}"
            "gid=${host.userGroup}"
            "dir_mode=0555"
            "file_mode=0444"
            "vers=2.0"
            "sec=ntlmssp"
            "ro"
          ];
          mountConfig.TimeoutSec = "15s";
        }
      ];

      automounts = [
        {
          description = "Automount Infernalnexus ROM collection";
          where = romRoot;
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "10min";
            DirectoryMode = "0755";
          };
        }
      ];

      user.services.helix-emulation-prepare = {
        description = "Prepare NAS-backed emulation paths for ${host.displayName}";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session-pre.target" ];
        unitConfig.ConditionUser = host.user;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${prepare}/bin/helix-emulation-prepare";
        };
      };
    };

    environment.systemPackages = [
      pkgs.igir
      pkgs.skyscraper
      requireNas
      discover
      prepare
      datIndex
      auditArcade
      scrape
      status
      pcsx2Launcher
      rpcs3Launcher
      shadps4Launcher
      mameLauncher
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
