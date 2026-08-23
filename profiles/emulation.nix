{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.emulation;
  nasRoot = "/mnt/infernalnexus/nas1";
  romRoot = "${nasRoot}/roms";
  emulationRoot = "${nasRoot}/Emulation";
  arcadeRoot = "${romRoot}/MAME 0.275 ROMs (merged, inc CHDs)";

  retroarch = pkgs.retroarch.withCores (
    cores: with cores; [
      bsnes
    ]
  );

  prepare = pkgs.writeShellApplication {
    name = "helix-emulation-prepare";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
    ];
    text = ''
      set -eu

      root=${lib.escapeShellArg emulationRoot}
      rom_root=${lib.escapeShellArg romRoot}

      if ! mountpoint -q ${lib.escapeShellArg nasRoot}; then
        printf 'NAS is not mounted at %s\n' ${lib.escapeShellArg nasRoot} >&2
        exit 1
      fi

      mkdir -p \
        "$root/bios" \
        "$root/saves" \
        "$root/states" \
        "$root/metadata" \
        "$root/tools/downloaded_media" \
        "$root/tools/skyscraper-home" \
        "$root/tools/dat-index" \
        "$root/tools/reports" \
        "$root/roms"

      link_system() {
        system_name=$1
        source_name=$2
        target="$root/roms/$system_name"
        source="$rom_root/$source_name"

        if [ ! -e "$source" ]; then
          printf 'ROM source absent, skipping: %s\n' "$source"
          return 0
        fi

        if [ -e "$target" ] && [ ! -L "$target" ]; then
          printf 'Refusing to replace non-symlink path: %s\n' "$target" >&2
          return 1
        fi

        ln -sfn "$source" "$target"
      }

      link_system ps2 PS2
      link_system ps3 PS3
      link_system ps4 PS4
      link_system snes SNES
      link_system arcade 'MAME 0.275 ROMs (merged, inc CHDs)'

      printf 'Prepared NAS-backed emulation tree at %s\n' "$root"
    '';
  };

  datIndex = pkgs.writeShellApplication {
    name = "helix-emulation-index-dats";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.util-linux
    ];
    text = ''
      set -eu

      source_root=${lib.escapeShellArg romRoot}
      output=${lib.escapeShellArg "${emulationRoot}/tools/dat-index/arcade-dats.txt"}

      if ! mountpoint -q ${lib.escapeShellArg nasRoot}; then
        printf 'NAS is not mounted at %s\n' ${lib.escapeShellArg nasRoot} >&2
        exit 1
      fi

      mkdir -p "$(dirname "$output")"
      find "$source_root" -type f \
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
      pkgs.findutils
      pkgs.igir
      datIndex
    ];
    text = ''
      set -eu

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

      platform=''${1:-}
      source=''${2:-screenscraper}
      case "$platform" in
        ps2|ps3|ps4|snes|arcade) ;;
        *)
          printf 'Usage: helix-emulation-scrape {ps2|ps3|ps4|snes|arcade} [scraper-source]\n' >&2
          exit 2
          ;;
      esac

      input=${lib.escapeShellArg "${emulationRoot}/roms"}/"$platform"
      media=${lib.escapeShellArg "${emulationRoot}/tools/downloaded_media"}/"$platform"
      metadata=${lib.escapeShellArg "${emulationRoot}/metadata"}/"$platform"
      scraper_home=${lib.escapeShellArg "${emulationRoot}/tools/skyscraper-home"}

      if [ ! -e "$input" ]; then
        printf 'ROM path is missing: %s\n' "$input" >&2
        printf 'Run helix-emulation-prepare first.\n' >&2
        exit 1
      fi

      mkdir -p "$media" "$metadata" "$scraper_home"
      export HOME="$scraper_home"

      printf 'Gathering %s metadata/artwork from %s...\n' "$platform" "$source"
      Skyscraper -p "$platform" -s "$source" -i "$input"
      printf 'Generating ES-DE metadata and artwork on the NAS...\n'
      exec Skyscraper -p "$platform" -f esde -i "$input" -g "$metadata" -o "$media"
    '';
  };

  status = pkgs.writeShellApplication {
    name = "helix-emulation-status";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      printf 'Helix emulation module: enabled\n'
      printf 'NAS root: %s\n' ${lib.escapeShellArg nasRoot}
      printf 'ROM root: %s\n' ${lib.escapeShellArg romRoot}
      printf 'Managed emulation root: %s\n' ${lib.escapeShellArg emulationRoot}
      printf '\nExpected systems:\n'
      for system in ps2 ps3 ps4 snes arcade; do
        path=${lib.escapeShellArg "${emulationRoot}/roms"}/"$system"
        if [ -e "$path" ]; then
          printf '  %-7s %s\n' "$system" "$(readlink -f "$path")"
        else
          printf '  %-7s missing\n' "$system"
        fi
      done
    '';
  };
in
{
  options.helix.emulation.enable = lib.mkEnableOption "NAS-first emulator stack";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.pcsx2
      pkgs.rpcs3
      pkgs.shadps4
      pkgs.mame
      pkgs.igir
      pkgs.skyscraper
      retroarch
      prepare
      datIndex
      auditArcade
      scrape
      status
    ];

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
