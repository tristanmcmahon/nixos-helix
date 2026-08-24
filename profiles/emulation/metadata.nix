{
  lib,
  pkgs,
  romRoot,
  emulationRoot,
  arcadeRoot,
  requireNas,
  prepare,
}:

let
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
in
{
  inherit datIndex auditArcade scrape;
}
