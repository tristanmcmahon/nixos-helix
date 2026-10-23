#!/usr/bin/env bash

set -euo pipefail

# HELIX_SSD_ROOTS is "id=mountpoint ..." and is generated from config/helix.nix
# by profiles/gaming.nix, so the disk list is not repeated here.
ssd_roots=${HELIX_SSD_ROOTS:?HELIX_SSD_ROOTS is set by profiles/gaming.nix}
ssd_id=a
# Fallout 4 is about 30 GiB and Fallout London about 40 GiB with its download.
min_free_gib=90

usage() {
  printf 'Usage: helix-fallout-london-setup [--ssd a|b|c]\n'
  printf 'Prepare a data SSD and Heroic for Fallout 4 + Fallout London (GOG).\n'
  printf 'Default SSD: %s. GOG login and the installs themselves stay in Heroic.\n' "$ssd_id"
}

while (($#)); do
  case $1 in
    --help)
      usage
      exit 0
      ;;
    --ssd)
      [[ $# -ge 2 ]] || {
        usage >&2
        exit 2
      }
      ssd_id=$2
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

mount_point=
for entry in $ssd_roots; do
  [[ ${entry%%=*} == "$ssd_id" ]] && mount_point=${entry#*=}
done
[[ -n $mount_point ]] || {
  printf 'Unknown SSD "%s". Known: %s\n' "$ssd_id" "$ssd_roots" >&2
  exit 2
}

if pgrep -x heroic >/dev/null; then
  printf 'Heroic is open. Close it before running helix-fallout-london-setup.\n' >&2
  exit 1
fi

# The SSDs are nofail mounts; writing to an unmounted one would fill the
# system disk under the empty mount point.
mountpoint -q "$mount_point" || {
  printf '%s is not mounted. Refusing to write elsewhere.\n' "$mount_point" >&2
  exit 1
}
[[ -w $mount_point/data ]] || {
  printf '%s/data is missing or not writable by %s.\n' "$mount_point" "$USER" >&2
  exit 1
}
free_gib=$(df --output=avail -BG "$mount_point" | tail -n 1 | tr -dc '0-9')
((free_gib >= min_free_gib)) || {
  printf '%s has %s GiB free; at least %s GiB is needed.\n' \
    "$mount_point" "$free_gib" "$min_free_gib" >&2
  exit 1
}

games_root=$mount_point/data/games/heroic
install -d "$games_root/installs" "$games_root/prefixes/fallout"

heroic_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/heroic
heroic_config=$heroic_dir/config.json
install -d "$heroic_dir"
if [[ -e $heroic_config ]]; then
  cp --update=none --preserve=timestamps "$heroic_config" "$heroic_config.pre-helix-fallout"
fi
base='{}'
if jq -e 'type == "object"' "$heroic_config" >/dev/null 2>&1; then
  base=$(jq -c . "$heroic_config")
fi
config_tmp=$(mktemp "$heroic_dir/config.json.XXXXXX")
trap 'rm -f "$config_tmp"' EXIT
# Only the install and prefix locations are set; logins and every other
# Heroic setting stay as they are.
jq -n --argjson base "$base" --arg installs "$games_root/installs" \
  --arg prefix "$games_root/prefixes" '
    $base
    | .version = (.version // "v0")
    | .defaultSettings = ((.defaultSettings // {}) + {
        defaultInstallPath: $installs,
        winePrefix: $prefix
      })
  ' >"$config_tmp"
chmod 0644 "$config_tmp"
mv "$config_tmp" "$heroic_config"

cat <<EOF
Prepared $games_root (${free_gib} GiB free on $mount_point).
Heroic now installs games to $games_root/installs.

Remaining steps, which need your GOG login and so stay in Heroic:
  1. Open Heroic and log in to GOG.
  2. Install Fallout 4 (GOG). In its settings choose a Proton-GE / Wine-GE
     runner and set the Wine prefix to $games_root/prefixes/fallout
  3. Launch Fallout 4 once, then close it.
  4. Install Fallout London (GOG) with the same runner and the same prefix,
     pointing the installer at the Fallout 4 folder if it asks. Heroic's
     install dialog can silently reset the prefix to its own default, so
     confirm it in Settings before the first launch.
  5. Start Fallout London from Heroic.

If a launch fails with a Steam Runtime digest-mismatch error, or Fallout
London's New Game boots vanilla Fallout 4, see the Gaming section of
docs/profiles.md for known workarounds.
EOF
