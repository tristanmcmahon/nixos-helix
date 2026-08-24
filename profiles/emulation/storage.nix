{
  lib,
  pkgs,
  nasRoot,
  nasSource,
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
in
{
  inherit requireNas discover prepare;
}
