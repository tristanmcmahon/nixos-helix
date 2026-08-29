#!/usr/bin/env bash

set -euo pipefail

doom_root=/mnt/games_nvme/doom
download_dir=$doom_root/downloads
iwad_dir=$doom_root/iwads
map_dir=$doom_root/maps
mod_dir=$doom_root/mods

if [[ ${1:-} == --help ]]; then
  printf 'Usage: helix-doom-setup\n'
  printf 'Populate %s with Steam IWADs and the curated Doom mod set.\n' "$doom_root"
  exit 0
fi
if (($#)); then
  printf 'Usage: helix-doom-setup\n' >&2
  exit 2
fi

if pgrep -x DoomRunner >/dev/null; then
  printf 'DoomRunner is open. Close it before running helix-doom-setup.\n' >&2
  exit 1
fi

mountpoint -q /mnt/games_nvme || {
  printf '/mnt/games_nvme is not mounted. Refusing to write elsewhere.\n' >&2
  exit 1
}
install -d "$download_dir" "$iwad_dir" "$map_dir" "$mod_dir"

steam_libraries=(/home/tristan/.local/share/Steam)
for library_file in \
  /home/tristan/.local/share/Steam/steamapps/libraryfolders.vdf \
  /home/tristan/.steam/steam/steamapps/libraryfolders.vdf \
  /home/tristan/.steam/debian-install/steamapps/libraryfolders.vdf; do
  [[ -r $library_file ]] || continue
  while IFS= read -r library; do
    [[ -n $library ]] && steam_libraries+=("$library")
  done < <(
    sed -n 's/^[[:space:]]*"path"[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$library_file"
  )
done

steam_roots=()
for candidate in \
  /home/tristan/.local/share/Steam/steamapps/common \
  /mnt/games_nvme/steamapps/common \
  /mnt/games_nvme/SteamLibrary/steamapps/common; do
  [[ -d $candidate ]] && steam_roots+=("$candidate")
done
for library in "${steam_libraries[@]}"; do
  candidate=$library/steamapps/common
  [[ -d $candidate ]] && steam_roots+=("$candidate")
done

if ((${#steam_roots[@]})); then
  while IFS= read -r -d '' iwad; do
    case ${iwad##*/} in
      [Dd][Oo][Oo][Mm].[Ww][Aa][Dd] | [Dd][Oo][Oo][Mm]2.[Ww][Aa][Dd] | \
        [Pp][Ll][Uu][Tt][Oo][Nn][Ii][Aa].[Ww][Aa][Dd] | \
        [Tt][Nn][Tt].[Ww][Aa][Dd] | [Nn][Ee][Rr][Vv][Ee].[Ww][Aa][Dd])
        iwad_name=$(basename "$iwad" | tr '[:lower:]' '[:upper:]')
        ln -sfn "$(realpath "$iwad")" "$iwad_dir/$iwad_name"
        ;;
    esac
  done < <(find "${steam_roots[@]}" -type f -iname '*.wad' -print0)
fi

[[ -e $iwad_dir/DOOM2.WAD ]] || {
  printf 'Could not find DOOM2.WAD in the installed Steam libraries.\n' >&2
  printf 'Steam libraries searched:\n' >&2
  printf '  %s\n' "${steam_roots[@]}" >&2
  exit 1
}

doomrunner_data_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}/DoomRunner
doomrunner_options=$doomrunner_data_dir/options.json
gzdoom_id=8b9019b0-6141-4e08-a5dd-helixgzdoom
uzdoom_id=8a2b29e5-daaf-45c8-b162-helixuzdoom
install -d "$doomrunner_data_dir"

core_base={}
if [[ -e $doomrunner_options ]]; then
  cp --no-clobber --preserve=timestamps \
    "$doomrunner_options" "$doomrunner_options.pre-helix-doom"
fi
if jq -e 'type == "object"' "$doomrunner_options" >/dev/null 2>&1; then
  core_base=$(jq -c . "$doomrunner_options")
fi
core_tmp=$(mktemp "$doomrunner_data_dir/options.json.XXXXXX")
jq -n \
  --argjson base "$core_base" \
  --arg home "$HOME" \
  --arg iwad_dir "$iwad_dir" \
  --arg map_dir "$map_dir" \
  --arg mod_dir "$mod_dir" \
  --arg gzdoom_id "$gzdoom_id" \
  --arg uzdoom_id "$uzdoom_id" '
    def gameplay_preset($name; $engine; $mod): {
      name: $name,
      selected_engine: $engine,
      selected_config: "",
      selected_IWAD: ($iwad_dir + "/DOOM2.WAD"),
      selected_mappacks: [],
      mods: [{path: $mod, checked: true}],
      load_maps_after_mods: false,
      compatibility_options: {
        compat_mode: -1,
        compatflags1: 0,
        compatflags2: 0
      },
      alternative_paths: {
        config_dir: "",
        save_dir: "",
        demo_dir: "",
        screenshot_dir: ""
      },
      additional_args: "",
      env_vars: {}
    };

    [
      gameplay_preset(
        "Brutal Doom";
        $gzdoom_id;
        ($mod_dir + "/brutal-doom-v21/brutalv21.pk3")
      ),
      gameplay_preset(
        "Doom Deluxe";
        $uzdoom_id;
        ($mod_dir + "/doom-deluxe-beta1/doom_deluxe_beta1.pk3")
      )
    ] as $gameplay_presets |
    ($gameplay_presets | map(.name)) as $gameplay_names |
    $base |
    .version = "1.9.2" |
    .engines = (($base.engines // {}) + {
      default_engine: $gzdoom_id,
      engine_list: (
        (($base.engines.engine_list // []) | map(select(
          .id != $gzdoom_id and .id != $uzdoom_id and
          .path != "/run/current-system/sw/bin/gzdoom" and
          .path != "/run/current-system/sw/bin/uzdoom"
        ))) + [
          {
            id: $gzdoom_id, name: "GZDoom",
            path: "/run/current-system/sw/bin/gzdoom",
            config_dir: ($home + "/.config/gzdoom"),
            data_dir: ($home + "/.config/gzdoom"), family: "ZDoom"
          },
          {
            id: $uzdoom_id, name: "UZDoom",
            path: "/run/current-system/sw/bin/uzdoom",
            config_dir: ($home + "/.config/uzdoom"),
            data_dir: ($home + "/.config/uzdoom"), family: "ZDoom"
          }
        ]
      )
    }) |
    .IWADs = {
      auto_update: true,
      directory: $iwad_dir,
      search_subdirs: false,
      default_iwad: ($iwad_dir + "/DOOM2.WAD")
    } |
    .maps = (($base.maps // {}) + {directory: $map_dir}) |
    .mods = (($base.mods // {}) + {last_used_dir: $mod_dir}) |
    .presets = (
      (($base.presets // []) | map(select(
        .name as $name | ($gameplay_names | index($name)) == null
      ))) + $gameplay_presets
    ) |
    .selected_preset = "Brutal Doom"
  ' > "$core_tmp"
mv "$core_tmp" "$doomrunner_options"

download() {
  local url=$1
  local destination=$2
  local temporary=$destination.part
  [[ -s $destination ]] && return
  printf 'Downloading %s\n' "$(basename "$destination")"
  curl --fail --location --retry 3 --user-agent 'Mozilla/5.0' \
    --output "$temporary" "$url"
  mv "$temporary" "$destination"
}

install_zip() {
  local name=$1
  local url=$2
  local archive=$download_dir/$name.zip
  download "$url" "$archive"
  install -d "$mod_dir/$name"
  unzip -q -o "$archive" -d "$mod_dir/$name"
}

install -d "$mod_dir/brutal-doom-v21"
download \
  'https://allfearthesentinel.com/zandronum/download.php?file=brutalv21.pk3' \
  "$mod_dir/brutal-doom-v21/brutalv21.pk3"
[[ $(stat -c %s "$mod_dir/brutal-doom-v21/brutalv21.pk3") == 86566833 ]] || {
  printf 'Unexpected size for brutalv21.pk3; refusing to use it.\n' >&2
  exit 1
}

install -d "$mod_dir/doom-deluxe-beta1"
download \
  'https://allfearthesentinel.com/zandronum/download.php?file=doom_deluxe_beta1.pk3' \
  "$mod_dir/doom-deluxe-beta1/doom_deluxe_beta1.pk3"
[[ $(stat -c %s "$mod_dir/doom-deluxe-beta1/doom_deluxe_beta1.pk3") == 49596148 ]] || {
  printf 'Unexpected size for doom_deluxe_beta1.pk3; refusing to use it.\n' >&2
  exit 1
}

idgames=https://www.gamers.org/pub/idgames/levels/doom2
install_zip eviternity-ii "$idgames/Ports/megawads/eviternityii.zip"
install_zip ancient-aliens "$idgames/Ports/megawads/aaliens.zip"
install_zip sunlust "$idgames/Ports/megawads/sunlust.zip"
install_zip going-down "$idgames/Ports/megawads/gd.zip"
install_zip valiant "$idgames/Ports/megawads/valiant.zip"
install_zip back-to-saturn-x-e1 "$idgames/megawads/btsx_e1.zip"
install_zip back-to-saturn-x-e2 "$idgames/megawads/btsx_e2.zip"
install_zip alien-vendetta "$idgames/megawads/av.zip"

map_collections=(
  eviternity-ii
  ancient-aliens
  sunlust
  going-down
  valiant
  back-to-saturn-x-e1
  back-to-saturn-x-e2
  alien-vendetta
)
for collection in "${map_collections[@]}"; do
  while IFS= read -r -d '' map_file; do
    ln -sfn "$(realpath "$map_file")" \
      "$map_dir/$collection--$(basename "$map_file")"
  done < <(find "$mod_dir/$collection" -type f -iname '*.wad' -print0)
done

map_files_json() {
  find "$map_dir" -maxdepth 1 -type l -name "$1--*" -print \
    | LC_ALL=C sort \
    | jq -Rsc 'split("\n") | map(select(length > 0))'
}

gameplay_files_json() {
  local directory=$1
  local files
  files=$(
    find "$directory" -type f \
      \( -iname '*.pk3' -o -iname '*.pk7' -o -iname '*.ipk3' \) -print \
      | LC_ALL=C sort
  )
  if [[ -z $files ]]; then
    files=$(find "$directory" -type f -iname '*.wad' -print | LC_ALL=C sort)
  fi
  [[ -n $files ]] || {
    printf 'No playable mod file found in %s\n' "$directory" >&2
    exit 1
  }
  jq -Rn --arg files "$files" \
    '$files | split("\n") | map(select(length > 0) | {path: ., checked: true})'
}

brutal_files=$(gameplay_files_json "$mod_dir/brutal-doom-v21")
doom_deluxe_files=$(gameplay_files_json "$mod_dir/doom-deluxe-beta1")
eviternity_files=$(map_files_json eviternity-ii)
ancient_aliens_files=$(map_files_json ancient-aliens)
sunlust_files=$(map_files_json sunlust)
going_down_files=$(map_files_json going-down)
valiant_files=$(map_files_json valiant)
btsx_e1_files=$(map_files_json back-to-saturn-x-e1)
btsx_e2_files=$(map_files_json back-to-saturn-x-e2)
alien_vendetta_files=$(map_files_json alien-vendetta)

base_json={}
if [[ -e $doomrunner_options ]]; then
  cp --no-clobber --preserve=timestamps \
    "$doomrunner_options" "$doomrunner_options.pre-helix-doom"
  if jq -e 'type == "object"' "$doomrunner_options" >/dev/null 2>&1; then
    base_json=$(jq -c . "$doomrunner_options")
  fi
fi

doomrunner_tmp=$(mktemp "$doomrunner_data_dir/options.json.XXXXXX")
trap 'rm -f "$doomrunner_tmp"' EXIT

jq -n \
  --argjson base "$base_json" \
  --arg home "$HOME" \
  --arg iwad_dir "$iwad_dir" \
  --arg map_dir "$map_dir" \
  --arg mod_dir "$mod_dir" \
  --arg gzdoom_id "$gzdoom_id" \
  --arg uzdoom_id "$uzdoom_id" \
  --argjson brutal "$brutal_files" \
  --argjson doom_deluxe "$doom_deluxe_files" \
  --argjson eviternity "$eviternity_files" \
  --argjson ancient_aliens "$ancient_aliens_files" \
  --argjson sunlust "$sunlust_files" \
  --argjson going_down "$going_down_files" \
  --argjson valiant "$valiant_files" \
  --argjson btsx_e1 "$btsx_e1_files" \
  --argjson btsx_e2 "$btsx_e2_files" \
  --argjson alien_vendetta "$alien_vendetta_files" '
    def preset($name; $engine; $maps; $mods): {
      name: $name,
      selected_engine: $engine,
      selected_config: "",
      selected_IWAD: ($iwad_dir + "/DOOM2.WAD"),
      selected_mappacks: $maps,
      mods: $mods,
      load_maps_after_mods: false,
      compatibility_options: {
        compat_mode: -1,
        compatflags1: 0,
        compatflags2: 0
      },
      alternative_paths: {
        config_dir: "",
        save_dir: "",
        demo_dir: "",
        screenshot_dir: ""
      },
      additional_args: "",
      env_vars: {}
    };

    [
      preset("Brutal Doom"; $gzdoom_id; []; $brutal),
      preset("Doom Deluxe"; $uzdoom_id; []; $doom_deluxe),
      preset("Eviternity II"; $gzdoom_id; $eviternity; []),
      preset("Ancient Aliens"; $gzdoom_id; $ancient_aliens; []),
      preset("Sunlust"; $gzdoom_id; $sunlust; []),
      preset("Going Down"; $gzdoom_id; $going_down; []),
      preset("Valiant"; $gzdoom_id; $valiant; []),
      preset("Back to Saturn X E1"; $gzdoom_id; $btsx_e1; []),
      preset("Back to Saturn X E2"; $gzdoom_id; $btsx_e2; []),
      preset("Alien Vendetta"; $gzdoom_id; $alien_vendetta; [])
    ] as $managed_presets |
    ($managed_presets | map(.name)) as $managed_names |
    {
      version: "1.9.2",
      launch_options: {
        launch_mode: 0, map_name: "", save_file: "", map_name_demo: "",
        demo_file_record: "", demo_file_replay: "",
        demo_file_resume_from: "", demo_file_resume_to: ""
      },
      multiplayer_options: {
        is_multiplayer: false, mult_role: 0, host_name: "", port: 5029,
        net_mode: 0, game_mode: 0, player_count: 2, team_damage: 0,
        time_limit: 0, frag_limit: 0, player_name: "", player_color: null
      },
      gameplay_options: {
        skill_idx: 1, skill_num: 1, no_monsters: false,
        fast_monsters: false, monsters_respawn: false,
        pistol_start: false, allow_cheats: false,
        dmflags1: 0, dmflags2: 0, dmflags3: 0
      },
      video_options: {monitor_idx: 0, resolution_x: 0, resolution_y: 0, show_fps: false},
      audio_options: {no_sound: false, no_sfx: false, no_music: false},
      global_options: {
        use_preset_name_as_config_dir: false,
        use_preset_name_as_save_dir: false,
        use_preset_name_as_demo_dir: false,
        use_preset_name_as_screenshot_dir: false,
        additional_args: "", cmd_prefix: "", env_vars: {}
      },
      use_absolute_paths: true,
      show_engine_output: true,
      close_on_launch: false,
      close_output_on_success: false,
      check_for_updates: true,
      ask_for_sandbox_permissions: true,
      wrap_lines_in_txt_viewer: false,
      options_storage: {
        launch_opts: 1, gameplay_opts: 1, compat_opts: 2,
        video_opts: 1, audio_opts: 1
      },
      geometry: {x: -2147483648, y: -2147483648, width: 0, height: 0},
      app_style: null,
      color_scheme: "default",
      preset_search: {panel_expanded: false, case_sensitive: false, use_regex: false},
      hide_map_label: false,
      selected_preset: "Brutal Doom"
    } * $base |
    .version = "1.9.2" |
    .engines = (($base.engines // {}) + {
      default_engine: $gzdoom_id,
      engine_list: (
        (($base.engines.engine_list // []) | map(select(
          .id != $gzdoom_id and .id != $uzdoom_id and
          .path != "/run/current-system/sw/bin/gzdoom" and
          .path != "/run/current-system/sw/bin/uzdoom"
        ))) + [
          {
            id: $gzdoom_id, name: "GZDoom",
            path: "/run/current-system/sw/bin/gzdoom",
            config_dir: ($home + "/.config/gzdoom"),
            data_dir: ($home + "/.config/gzdoom"), family: "ZDoom"
          },
          {
            id: $uzdoom_id, name: "UZDoom",
            path: "/run/current-system/sw/bin/uzdoom",
            config_dir: ($home + "/.config/uzdoom"),
            data_dir: ($home + "/.config/uzdoom"), family: "ZDoom"
          }
        ]
      )
    }) |
    .IWADs = {
      auto_update: true,
      directory: $iwad_dir,
      search_subdirs: false,
      default_iwad: ($iwad_dir + "/DOOM2.WAD")
    } |
    .maps = (($base.maps // {}) + {
      directory: $map_dir, sort_column: 0, sort_order: 0, show_icons: false
    }) |
    .mods = (($base.mods // {}) + {last_used_dir: $mod_dir, show_icons: true}) |
    .presets = (
      (($base.presets // []) | map(select(
        .name as $name | ($managed_names | index($name)) == null
      ))) + $managed_presets
    ) |
    .selected_preset = "Brutal Doom"
  ' > "$doomrunner_tmp"

mv "$doomrunner_tmp" "$doomrunner_options"
trap - EXIT

printf '\nDoom is ready in %s\n' "$doom_root"
printf 'DoomRunner is configured with both engines and 10 ready-to-launch presets.\n'
printf 'Run: doomrunner\n'
