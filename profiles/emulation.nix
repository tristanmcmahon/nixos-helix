{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.emulation;
  nasRoot = "/mnt/infernalnexus/nas1";
  nasSource = "//192.168.1.8/nas1";
  romRoot = "/mnt/infernalnexus/roms";
  romSource = "//192.168.1.8/roms";
  emulationRoot = "${nasRoot}/Emulation";
  arcadeRoot = "${emulationRoot}/roms/arcade";
  stateRoot = "${emulationRoot}/state";

  retroarch = pkgs.retroarch.withCores (
    cores: with cores; [
      bsnes
    ]
  );

  requireNas = pkgs.writeShellApplication {
    name = "helix-emulation-require-nas";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      set -eu

      verify_cifs() {
        mount_path=$1
        expected_source=$2

        ls -d "$mount_path/." >/dev/null 2>&1 || true
        actual_source=$(findmnt -rn --target "$mount_path" --types cifs -o SOURCE || true)
        if [ "''${actual_source%/}" != "$expected_source" ]; then
          printf 'Expected CIFS source %s at %s, found %s\n' \
            "$expected_source" "$mount_path" "''${actual_source:-nothing}" >&2
          exit 1
        fi
      }

      # Touch both autofs paths, then reject a bare systemd automount stub or a
      # different share. ROMs are authoritative on the dedicated read-only
      # Synology share used by tfpga; writable state remains on nas1.
      verify_cifs ${lib.escapeShellArg nasRoot} ${lib.escapeShellArg nasSource}
      verify_cifs ${lib.escapeShellArg romRoot} ${lib.escapeShellArg romSource}
    '';
  };

  discover = pkgs.writeShellApplication {
    name = "helix-emulation-discover";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnused
    ];
    text = ''
      set -eu

      ${requireNas}/bin/helix-emulation-require-nas

      nas_root=${lib.escapeShellArg nasRoot}
      rom_root=${lib.escapeShellArg romRoot}
      report=${lib.escapeShellArg "${emulationRoot}/tools/reports/discovery.txt"}

      mkdir -p "$(dirname "$report")"
      {
        printf 'Helix emulation NAS discovery\n'
        printf 'NAS root: %s\n' "$nas_root"
        printf 'ROM root: %s\n\n' "$rom_root"

        printf 'Top-level ROM directories:\n'
        if [ -d "$rom_root" ]; then
          find "$rom_root" -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' | sort
        else
          printf '  ROM root is absent\n'
        fi

        printf '\nBIOS/firmware directory candidates (depth <= 4):\n'
        find "$rom_root" -mindepth 1 -maxdepth 4 -type d \
          \( -iname bios -o -iname firmware \) -print 2>/dev/null | sort | sed 's/^/  /'

        printf '\nDAT/XML definitions (depth <= 4):\n'
        find "$rom_root" -mindepth 1 -maxdepth 4 -type f \
          \( -iname '*.dat' -o -iname '*.xml' \) -print 2>/dev/null | sort | sed 's/^/  /'
      } | tee "$report"

      printf '\nDiscovery report saved to %s\n' "$report"
    '';
  };

  prepare = pkgs.writeShellApplication {
    name = "helix-emulation-prepare";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      discover
    ];
    text = ''
      set -eu

      ${requireNas}/bin/helix-emulation-require-nas

      root=${lib.escapeShellArg emulationRoot}
      rom_root=${lib.escapeShellArg romRoot}
      state_root=${lib.escapeShellArg stateRoot}

      mkdir -p \
        "$root/bios/sources" \
        "$root/saves/arcade" \
        "$root/saves/ps2" \
        "$root/saves/ps3" \
        "$root/saves/ps4" \
        "$root/saves/snes" \
        "$root/states/arcade" \
        "$root/states/ps2" \
        "$root/states/ps3" \
        "$root/states/ps4" \
        "$root/states/snes" \
        "$root/screenshots/arcade" \
        "$root/screenshots/ps2" \
        "$root/screenshots/ps3" \
        "$root/screenshots/ps4" \
        "$root/screenshots/snes" \
        "$root/metadata" \
        "$root/tools/downloaded_media" \
        "$root/tools/skyscraper-home" \
        "$root/tools/dat-index" \
        "$root/tools/reports" \
        "$root/roms" \
        "$state_root"

      resolve_source() {
        prefer_nested() {
          resolved=$1
          if [ -d "$resolved/roms" ]; then
            printf '%s\n' "$resolved/roms"
          else
            printf '%s\n' "$resolved"
          fi
        }

        for candidate in "$@"; do
          if [ -d "$rom_root/$candidate" ]; then
            prefer_nested "$rom_root/$candidate"
            return 0
          fi
        done

        for candidate in "$@"; do
          found=$(find "$rom_root" -mindepth 1 -maxdepth 1 -type d \
            -iname "$candidate" -print -quit 2>/dev/null || true)
          if [ -n "$found" ]; then
            prefer_nested "$found"
            return 0
          fi
        done

        return 1
      }

      link_system() {
        system_name=$1
        shift
        source=$(resolve_source "$@" || true)
        target="$root/roms/$system_name"

        if [ -z "$source" ]; then
          printf 'ROM source absent, skipping %s (aliases: %s)\n' \
            "$system_name" "$*"
          return 0
        fi

        if { [ -e "$target" ] || [ -L "$target" ]; } && [ ! -L "$target" ]; then
          printf 'Refusing to replace non-symlink path: %s\n' "$target" >&2
          return 1
        fi

        ln -sfn "$source" "$target"
        printf 'Resolved %-7s -> %s\n' "$system_name" "$source"
      }

      link_system ps2 PS2 'PlayStation 2' 'Playstation 2' 'Sony PlayStation 2'
      link_system ps3 PS3 'PlayStation 3' 'Playstation 3' 'Sony PlayStation 3'
      link_system ps4 PS4 'PlayStation 4' 'Playstation 4' 'Sony PlayStation 4'
      link_system snes SNES 'Super Nintendo' 'Super Nintendo Entertainment System'
      link_system arcade 'MAME 0.275 ROMs (merged, inc CHDs)' 'MAME 0.275' MAME arcade

      find "$root/bios/sources" -mindepth 1 -maxdepth 1 -type l -delete
      bios_index=0
      while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        bios_index=$((bios_index + 1))
        ln -sfn "$candidate" "$root/bios/sources/source-$bios_index"
      done < <(
        find "$rom_root" -mindepth 1 -maxdepth 4 -type d \
          \( -iname bios -o -iname firmware \) -print 2>/dev/null | sort
      )
      printf 'Exposed %s BIOS/firmware candidate directories under %s\n' \
        "$bios_index" "$root/bios/sources"

      helix-emulation-discover >/dev/null
      printf 'Prepared NAS-backed emulation tree at %s\n' "$root"
    '';
  };

  datIndex = pkgs.writeShellApplication {
    name = "helix-emulation-index-dats";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      set -eu

      ${requireNas}/bin/helix-emulation-require-nas

      source_root=${lib.escapeShellArg romRoot}
      output=${lib.escapeShellArg "${emulationRoot}/tools/dat-index/arcade-dats.txt"}

      mkdir -p "$(dirname "$output")"
      find "$source_root" -mindepth 1 -maxdepth 4 -type f \
        \( -iname '*.dat' -o -iname '*.xml' \) \
        -print | sort > "$output"

      count=$(wc -l < "$output")
      printf 'Indexed %s DAT/XML files into %s\n' "$count" "$output"
    '';
  };

  auditArcade = pkgs.writeShellApplication {
    name = "helix-emulation-audit-arcade";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.igir
      datIndex
    ];
    text = ''
      set -eu

      ${prepare}/bin/helix-emulation-prepare >/dev/null

      roms=${lib.escapeShellArg arcadeRoot}
      dat_index=${lib.escapeShellArg "${emulationRoot}/tools/dat-index/arcade-dats.txt"}
      report=${lib.escapeShellArg "${emulationRoot}/tools/reports/arcade-0.275.csv"}

      if [ ! -d "$roms" ]; then
        printf 'Arcade ROM tree not found: %s\n' "$roms" >&2
        exit 1
      fi

      if [ ! -s "$dat_index" ]; then
        helix-emulation-index-dats >/dev/null
      fi

      mapfile -t dats < <(grep -Ei 'mame[^/]*0[._ -]?275|0[._ -]?275[^/]*mame' "$dat_index" || true)
      if [ "''${#dats[@]}" -eq 0 ]; then
        mapfile -t dats < <(grep -Ei '/MAME 0[.]275 ROMs .*\.(dat|xml)$' "$dat_index" || true)
      fi

      if [ "''${#dats[@]}" -eq 0 ]; then
        printf 'No MAME 0.275 DAT/XML was found on the NAS.\n' >&2
        printf 'Indexed definitions are in %s\n' "$dat_index" >&2
        exit 1
      fi

      dat_args=()
      for dat in "''${dats[@]}"; do
        dat_args+=(--dat "$dat")
      done

      mkdir -p "$(dirname "$report")"
      printf 'Read-only Igir audit of the MAME 0.275 collection using %s DAT file(s).\n' "''${#dats[@]}"
      igir report \
        "''${dat_args[@]}" \
        --input "$roms" \
        --input-checksum-quick \
        --report-output "$report"
      printf 'Report: %s\n' "$report"
    '';
  };

  scrape = pkgs.writeShellApplication {
    name = "helix-emulation-scrape";
    runtimeInputs = [ pkgs.skyscraper ];
    text = ''
      set -eu

      ${prepare}/bin/helix-emulation-prepare >/dev/null

      platform=''${1:-}
      source=''${2:-screenscraper}
      case "$platform" in
        ps2|snes|arcade) ;;
        ps3|ps4)
          printf 'Skyscraper does not support %s; automated scraping is available for ps2, snes, and arcade only.\n' \
            "$platform" >&2
          exit 2
          ;;
        *)
          printf 'Usage: helix-emulation-scrape {ps2|snes|arcade} [scraper-source]\n' >&2
          exit 2
          ;;
      esac

      input=${lib.escapeShellArg "${emulationRoot}/roms"}/"$platform"
      media=${lib.escapeShellArg "${emulationRoot}/tools/downloaded_media"}/"$platform"
      metadata=${lib.escapeShellArg "${emulationRoot}/metadata"}/"$platform"
      scraper_home=${lib.escapeShellArg "${emulationRoot}/tools/skyscraper-home"}

      if [ ! -e "$input" ]; then
        printf 'ROM path is missing: %s\n' "$input" >&2
        exit 1
      fi

      mkdir -p "$media" "$metadata" "$scraper_home"
      export HOME="$scraper_home"
      export XDG_CACHE_HOME="$scraper_home/.cache"
      export XDG_CONFIG_HOME="$scraper_home/.config"
      export XDG_DATA_HOME="$scraper_home/.local/share"
      export XDG_STATE_HOME="$scraper_home/.local/state"

      printf 'Gathering %s metadata/artwork from %s...\n' "$platform" "$source"
      Skyscraper -p "$platform" -s "$source" -i "$input"
      printf 'Generating ES-DE metadata and artwork on the NAS...\n'
      exec Skyscraper -p "$platform" -f esde -i "$input" -g "$metadata" -o "$media"
    '';
  };

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
            "uid=tristan"
            "gid=users"
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
