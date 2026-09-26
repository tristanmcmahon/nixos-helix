{
  lib,
  pkgs,
  romRoot,
  romSource,
  emulationRoot,
  stateRoot,
}:

let
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

      # Touch the autofs path, then reject a bare systemd automount stub or a
      # different share. ROMs are authoritative on the dedicated read-only
      # Synology share used by tfpga; writable state remains on GAMES_NVME.
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

      rom_root=${lib.escapeShellArg romRoot}
      report=${lib.escapeShellArg "${emulationRoot}/tools/reports/discovery.txt"}

      mkdir -p "$(dirname "$report")"
      {
        printf 'Helix emulation NAS discovery\n'
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

  scrape = pkgs.writeShellApplication {
    name = "helix-emulation-scrape";
    runtimeInputs = [ pkgs.skyscraper ];
    text = ''
      set -eu

      ${prepare}/bin/helix-emulation-prepare >/dev/null

      platform=''${1:-}
      source=''${2:-screenscraper}
      case "$platform" in
        ps2|snes) ;;
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
      printf 'Generating ES-DE metadata and artwork on GAMES_NVME...\n'
      exec Skyscraper -p "$platform" -f esde -i "$input" -g "$metadata" -o "$media"
    '';
  };

  status = pkgs.writeShellApplication {
    name = "helix-emulation-status";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      printf 'Helix emulation module: enabled\n'
      printf 'Read-only ROM root: %s\n' ${lib.escapeShellArg romRoot}
      printf 'SSD emulation root: %s\n' ${lib.escapeShellArg emulationRoot}
      printf 'Managed emulator state: %s\n' ${lib.escapeShellArg stateRoot}
      printf '\nResolved systems:\n'
      for system in ps2 ps3 ps4 snes; do
        path=${lib.escapeShellArg "${emulationRoot}/roms"}/"$system"
        if [ -e "$path" ]; then
          printf '  %-7s %s\n' "$system" "$(readlink -f "$path")"
        else
          printf '  %-7s missing\n' "$system"
        fi
      done
      printf '\nDiscovery report: %s\n' \
        ${lib.escapeShellArg "${emulationRoot}/tools/reports/discovery.txt"}
      printf 'Launch the Helix entries to keep ROMs read-only and mutable state on GAMES_NVME.\n'
    '';
  };
in
{
  inherit
    requireNas
    discover
    prepare
    scrape
    status
    ;
}
