#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

require_readable() {
  local path=$1
  [[ -r $path ]] || {
    printf 'Desktop release check: missing readable artifact: %s\n' "$path" >&2
    exit 1
  }
}

require_executable() {
  local path=$1
  [[ -x $path ]] || {
    printf 'Desktop release check: missing executable: %s\n' "$path" >&2
    exit 1
  }
}

require_contains() {
  local path=$1
  local expected=$2
  grep -qF -- "$expected" "$path" || {
    printf 'Desktop release check: %s lacks expected text: %s\n' "$path" "$expected" >&2
    exit 1
  }
}

# Facts the evaluation invariants already assert are not repeated here; these
# checks inspect built artefacts in ways evaluation cannot.
printf 'Checking Helix Graphite + Fern in the built default system...\n'
fern_scheme=$system_closure/sw/share/color-schemes/HelixGraphiteFern.colors
require_readable "$fern_scheme"
require_contains "$fern_scheme" 'Name=Helix Graphite Fern'
require_contains "$fern_scheme" 'ColorScheme=Helix Graphite Fern'
require_readable "$system_closure/sw/share/wallpapers/HelixGraphiteFern/contents/images/wallpaper.svg"
require_readable "$system_closure/sw/share/konsole/HelixGraphiteFern.colorscheme"
require_readable "$system_closure/sw/share/konsole/HelixGraphiteFern.profile"
sddm_theme=$system_closure/sw/share/sddm/themes/helix-graphite-fern/theme.conf
require_readable "$sddm_theme"
require_contains "$sddm_theme" 'HelixGraphiteFern/contents/images/wallpaper.svg'
require_executable "$system_closure/sw/bin/helix-apply-theme"
# Plasma/KDE helper commands are private runtime dependencies of
# helix-apply-theme; they need not all be exposed as global system commands.
# Their presence in the helper closure is verified below.
for theme in fern petrol plum oxide amber rosewood hotdog; do
  [[ -d $system_closure/etc/helix/themes/$theme ]]
done
[[ -x $system_closure/sw/bin/helix-theme ]]
"$system_closure/sw/bin/helix-theme" list | grep -qF 'regrettably available.'
"$system_closure/sw/bin/helix-apply-theme" --help | grep -qF -- '--force'
if "$system_closure/sw/bin/helix-apply-theme" --invalid >/dev/null 2>&1; then
  printf 'helix-apply-theme accepted an invalid argument.\n' >&2
  exit 1
fi
theme_helper=$(readlink -f "$system_closure/sw/bin/helix-apply-theme")
mapfile -t theme_closure < <(nix-store -qR "$theme_helper")
for theme_runtime_command in gsettings python3 plasma-apply-colorscheme \
  plasma-apply-desktoptheme plasma-apply-cursortheme plasma-apply-wallpaperimage \
  kwriteconfig6 install; do
  found_runtime_command=0
  for closure_path in "${theme_closure[@]}"; do
    if [[ -x $closure_path/bin/$theme_runtime_command ]]; then
      found_runtime_command=1
      break
    fi
  done
  ((found_runtime_command))
done
# Each login applies exactly one theme, from the session's rotation.
[[ ! -e $system_closure/etc/systemd/user/helix-graphite-fern-theme.service ]]
[[ -r $system_closure/etc/systemd/user/helix-ghostty-config.service ]]
for theme_asset in gtk-3.0-settings.ini gtk-4.0-settings.ini waybar.css mako.conf \
  fuzzel.ini steam.css wallpaper.svg apply-theme-settings.py; do
  [[ -r $system_closure/etc/helix/theme/$theme_asset ]]
done
[[ -x $system_closure/sw/bin/adwaita-steam-gtk ]]
[[ -x $system_closure/sw/bin/helix-apply-steam-theme ]]
"$system_closure/sw/bin/helix-apply-steam-theme" --help | grep -qF 'Close Steam first'
grep -qF -- '--adw-accent-rgb: 103, 184, 122' "$system_closure/etc/helix/theme/steam.css"
[[ -r $system_closure/sw/share/themes/Breeze-Dark/settings.ini ]]
[[ -r $system_closure/sw/share/icons/breeze-dark/index.theme ]]
grep -qF 'swaybg --image /home/tristan/.config/helix/theme/current/wallpaper.svg' "$hyprland_config"
grep -qF 'waybar --style /home/tristan/.config/helix/theme/current/waybar.css' "$hyprland_config"
grep -qF 'mako --config /home/tristan/.config/helix/theme/current/mako.conf' "$hyprland_config"
grep -qF 'fuzzel --config /home/tristan/.config/helix/theme/current/fuzzel.ini' "$hyprland_config"
# Validate the managed Ghostty config together with the built Main profile it
# includes, substituting a temporary path for the per-user profile file.
ghostty_validation_profile=$temporary_directory/ghostty-profile.ghostty
ghostty_validation_config=$temporary_directory/ghostty-config.ghostty
cp -- "$system_closure/etc/helix/ghostty/profiles/main.ghostty" "$ghostty_validation_profile"
sed "s|^config-file = .*|config-file = $ghostty_validation_profile|" \
  config/ghostty/config.ghostty > "$ghostty_validation_config"
grep -qxF "config-file = $ghostty_validation_profile" "$ghostty_validation_config"
"$system_closure/sw/bin/ghostty" +validate-config \
  --config-file="$ghostty_validation_config"
for ghostty_helper in ghostty-profile ghostty-surface-profile ghostty-surface-shell; do
  [[ -x $system_closure/sw/bin/$ghostty_helper ]]
done
ghostty_profile_launcher=$system_closure/sw/share/applications/ghostty-profile.desktop
[[ -r $ghostty_profile_launcher ]]
grep -qF 'X-KDE-Shortcuts=Meta+Shift+Return' "$ghostty_profile_launcher"

printf 'Checking ckb-next in the built default system...\n'
[[ -x $system_closure/sw/bin/ckb-next ]]
[[ -x $system_closure/sw/bin/ckb-next-daemon ]]
[[ -r $system_closure/etc/systemd/system/ckb-next.service ]]
ckb_daemon=$(readlink -f "$system_closure/sw/bin/ckb-next-daemon")
ckb_package=${ckb_daemon%/bin/ckb-next-daemon}
[[ -r $ckb_package/lib/udev/rules.d/99-ckb-next-daemon.rules ]]

