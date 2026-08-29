#!/usr/bin/env bash

set -euo pipefail

doom_root=/mnt/games_nvme/doom
download_dir=$doom_root/downloads
iwad_dir=$doom_root/iwads
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

mountpoint -q /mnt/games_nvme || {
  printf '/mnt/games_nvme is not mounted. Refusing to write elsewhere.\n' >&2
  exit 1
}
install -d "$download_dir" "$iwad_dir" "$mod_dir"

steam_roots=()
for candidate in \
  /home/tristan/.local/share/Steam/steamapps/common \
  /mnt/games_nvme/steamapps/common \
  /mnt/games_nvme/SteamLibrary/steamapps/common; do
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
  exit 1
}

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

download 'https://www.moddb.com/downloads/start/95667' "$download_dir/brutal-doom-v21.rar"
printf '%s  %s\n' a42f7a1f4fbec5b19591ece7f9811034 "$download_dir/brutal-doom-v21.rar" | md5sum -c -
install -d "$mod_dir/brutal-doom-v21"
7z x -y -bso0 -bsp0 -o"$mod_dir/brutal-doom-v21" "$download_dir/brutal-doom-v21.rar"

download 'https://www.moddb.com/downloads/start/307465' "$download_dir/doom-deluxe-beta1.zip"
printf '%s  %s\n' 46abfbe1b992fb48e1cac27e209d9560 "$download_dir/doom-deluxe-beta1.zip" | md5sum -c -
install -d "$mod_dir/doom-deluxe-beta1"
unzip -q -o "$download_dir/doom-deluxe-beta1.zip" -d "$mod_dir/doom-deluxe-beta1"

idgames=https://youfailit.net/pub/idgames/levels/doom2
install_zip eviternity-ii "$idgames/Ports/megawads/eviternity2.zip"
install_zip ancient-aliens "$idgames/Ports/megawads/aaliens.zip"
install_zip sunlust "$idgames/Ports/megawads/sunlust.zip"
install_zip going-down "$idgames/Ports/megawads/gd.zip"
install_zip valiant "$idgames/Ports/megawads/valiant.zip"
install_zip back-to-saturn-x-e1 "$idgames/megawads/btsx_e1.zip"
install_zip back-to-saturn-x-e2 "$idgames/megawads/btsx_e2.zip"
install_zip alien-vendetta "$idgames/megawads/av.zip"

printf '\nDoom is ready in %s\n' "$doom_root"
printf 'Open Doom Runner, add GZDoom and UZDoom as engines, then point its IWAD and map directories here.\n'
