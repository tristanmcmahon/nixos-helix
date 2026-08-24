{
  lib,
  pkgs,
  nasRoot,
  romRoot,
  emulationRoot,
  arcadeRoot,
  stateRoot,
  prepare,
}:

let
  retroarch = pkgs.retroarch.withCores (
    cores: with cores; [
      bsnes
    ]
  );

  mkNasLauncher =
    {
      name,
      emulator,
      package,
      extraArgs ? [ ],
    }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ pkgs.coreutils ];
      text = ''
        set -eu

        ${prepare}/bin/helix-emulation-prepare >/dev/null

        state_root=${lib.escapeShellArg "${stateRoot}/${emulator}"}
        mkdir -p \
          "$state_root/home" \
          "$state_root/config" \
          "$state_root/data" \
          "$state_root/cache" \
          "$state_root/state"

        export HOME="$state_root/home"
        export XDG_CONFIG_HOME="$state_root/config"
        export XDG_DATA_HOME="$state_root/data"
        export XDG_CACHE_HOME="$state_root/cache"
        export XDG_STATE_HOME="$state_root/state"

        exec ${lib.getExe package} ${lib.escapeShellArgs extraArgs} "$@"
      '';
    };

  pcsx2Launcher = mkNasLauncher {
    name = "helix-pcsx2";
    emulator = "pcsx2";
    package = pkgs.pcsx2;
  };

  rpcs3Launcher = mkNasLauncher {
    name = "helix-rpcs3";
    emulator = "rpcs3";
    package = pkgs.rpcs3;
  };

  shadps4Launcher = mkNasLauncher {
    name = "helix-shadps4";
    emulator = "shadps4";
    package = pkgs.shadps4;
  };

  mameLauncher = mkNasLauncher {
    name = "helix-mame";
    emulator = "mame";
    package = pkgs.mame;
    extraArgs = [
      "-rompath"
      arcadeRoot
    ];
  };

  retroarchLauncher = pkgs.writeShellApplication {
    name = "helix-retroarch";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu

      ${prepare}/bin/helix-emulation-prepare >/dev/null

      state_root=${lib.escapeShellArg "${stateRoot}/retroarch"}
      config_dir="$state_root/config/retroarch"
      config_file="$config_dir/retroarch.cfg"
      mkdir -p \
        "$state_root/home" \
        "$config_dir" \
        "$state_root/data" \
        "$state_root/cache" \
        "$state_root/state" \
        ${lib.escapeShellArg "${emulationRoot}/saves/snes"} \
        ${lib.escapeShellArg "${emulationRoot}/states/snes"} \
        ${lib.escapeShellArg "${emulationRoot}/screenshots/snes"}

      export HOME="$state_root/home"
      export XDG_CONFIG_HOME="$state_root/config"
      export XDG_DATA_HOME="$state_root/data"
      export XDG_CACHE_HOME="$state_root/cache"
      export XDG_STATE_HOME="$state_root/state"

      if [ ! -e "$config_file" ]; then
        cat > "$config_file" <<'EOF'
      savefile_directory = "${emulationRoot}/saves/snes"
      savestate_directory = "${emulationRoot}/states/snes"
      system_directory = "${emulationRoot}/bios"
      screenshot_directory = "${emulationRoot}/screenshots/snes"
      EOF
      fi

      exec ${lib.getExe retroarch} --config "$config_file" "$@"
    '';
  };

  desktopItems = [
    (pkgs.makeDesktopItem {
      name = "helix-pcsx2";
      desktopName = "PCSX2 (Helix NAS)";
      exec = "helix-pcsx2";
      icon = "applications-games";
      categories = [ "Game" ];
    })
    (pkgs.makeDesktopItem {
      name = "helix-rpcs3";
      desktopName = "RPCS3 (Helix NAS)";
      exec = "helix-rpcs3";
      icon = "applications-games";
      categories = [ "Game" ];
    })
    (pkgs.makeDesktopItem {
      name = "helix-shadps4";
      desktopName = "shadPS4 (Helix NAS)";
      exec = "helix-shadps4";
      icon = "applications-games";
      categories = [ "Game" ];
    })
    (pkgs.makeDesktopItem {
      name = "helix-mame";
      desktopName = "MAME (Helix NAS)";
      exec = "helix-mame";
      icon = "applications-games";
      categories = [ "Game" ];
    })
    (pkgs.makeDesktopItem {
      name = "helix-retroarch";
      desktopName = "RetroArch / SNES (Helix NAS)";
      exec = "helix-retroarch";
      icon = "applications-games";
      categories = [ "Game" ];
    })
  ];

  status = pkgs.writeShellApplication {
    name = "helix-emulation-status";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      printf 'Helix emulation module: enabled\n'
      printf 'NAS root: %s\n' ${lib.escapeShellArg nasRoot}
      printf 'ROM root: %s\n' ${lib.escapeShellArg romRoot}
      printf 'Managed emulation root: %s\n' ${lib.escapeShellArg emulationRoot}
      printf 'Managed emulator state: %s\n' ${lib.escapeShellArg stateRoot}
      printf '\nResolved systems:\n'
      for system in ps2 ps3 ps4 snes arcade; do
        path=${lib.escapeShellArg "${emulationRoot}/roms"}/"$system"
        if [ -e "$path" ]; then
          printf '  %-7s %s\n' "$system" "$(readlink -f "$path")"
        else
          printf '  %-7s missing\n' "$system"
        fi
      done
      printf '\nDiscovery report: %s\n' \
        ${lib.escapeShellArg "${emulationRoot}/tools/reports/discovery.txt"}
      printf 'Launch only the Helix NAS entries to keep emulator state off local SSDs.\n'
    '';
  };
in
{
  inherit
    desktopItems
    mameLauncher
    pcsx2Launcher
    retroarchLauncher
    rpcs3Launcher
    shadps4Launcher
    status
    ;
}
