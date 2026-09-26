#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

printf 'Checking Helix Graphite + Fern in the built default system...\n'
fern_scheme=$system_closure/sw/share/color-schemes/HelixGraphiteFern.colors
[[ -r $fern_scheme ]]
grep -qF 'Name=Helix Graphite Fern' "$fern_scheme"
grep -qF 'ColorScheme=Helix Graphite Fern' "$fern_scheme"
[[ -r $system_closure/sw/share/wallpapers/HelixGraphiteFern/contents/images/wallpaper.svg ]]
[[ -r $system_closure/sw/share/konsole/HelixGraphiteFern.colorscheme ]]
[[ -r $system_closure/sw/share/konsole/HelixGraphiteFern.profile ]]
[[ -r $system_closure/sw/share/sddm/themes/helix-graphite-fern/theme.conf ]]
grep -qF 'HelixGraphiteFern/contents/images/wallpaper.svg' \
  "$system_closure/sw/share/sddm/themes/helix-graphite-fern/theme.conf"
for theme_command in plasma-apply-colorscheme plasma-apply-desktoptheme \
  plasma-apply-cursortheme plasma-apply-wallpaperimage kwriteconfig6 helix-apply-theme; do
  [[ -x $system_closure/sw/bin/$theme_command ]]
done
for theme in fern petrol plum oxide amber rosewood hotdog; do
  [[ -d $system_closure/etc/helix/themes/$theme ]]
done
for scheme in Fern Petrol Plum Oxide Amber Rosewood HotDogStand; do
  [[ -r $system_closure/sw/share/color-schemes/HelixGraphite$scheme.colors ]]
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
theme_unit=$system_closure/etc/systemd/user/helix-graphite-fern-theme.service
[[ -r $theme_unit ]]
grep -qF 'ConditionUser=tristan' "$theme_unit"
grep -qF 'HOME=/home/tristan' "$theme_unit"
grep -qF 'XDG_CONFIG_HOME=/home/tristan/.config' "$theme_unit"
ghostty_unit=$system_closure/etc/systemd/user/helix-ghostty-config.service
[[ -r $ghostty_unit ]]
grep -qF 'ConditionUser=tristan' "$ghostty_unit"
grep -qF 'HOME=/home/tristan' "$ghostty_unit"
grep -qF 'XDG_CONFIG_HOME=/home/tristan/.config' "$ghostty_unit"
for theme_asset in gtk-3.0-settings.ini gtk-4.0-settings.ini waybar.css mako.conf \
  fuzzel.ini steam.css wallpaper.svg apply-theme-settings.py; do
  [[ -r $system_closure/etc/helix/theme/$theme_asset ]]
done
[[ -x $system_closure/sw/bin/adwaita-steam-gtk ]]
[[ -x $system_closure/sw/bin/helix-apply-steam-theme ]]
"$system_closure/sw/bin/helix-apply-steam-theme" --help | grep -qF 'Close Steam first'
grep -qF -- '--adw-accent-rgb: 103, 184, 122' config/theme/steam.css
[[ -r $system_closure/sw/share/themes/Breeze-Dark/settings.ini ]]
[[ -r $system_closure/sw/share/icons/breeze-dark/index.theme ]]
grep -qF 'swaybg --image /home/tristan/.config/helix/theme/current/wallpaper.svg' "$hyprland_config"
grep -qF 'waybar --style /home/tristan/.config/helix/theme/current/waybar.css' "$hyprland_config"
grep -qF 'mako --config /home/tristan/.config/helix/theme/current/mako.conf' "$hyprland_config"
grep -qF 'fuzzel --config /home/tristan/.config/helix/theme/current/fuzzel.ini' "$hyprland_config"
ghostty_config=config/ghostty/config.ghostty
ghostty_appearance=$ghostty_config
ghostty_validation_config=$ghostty_config
if grep -qF 'config-file = /home/tristan/.config/ghostty/profile.ghostty' "$ghostty_config"; then
  ghostty_appearance=config/ghostty/profiles/main.ghostty
  ghostty_validation_profile=$temporary_directory/ghostty-profile.ghostty
  ghostty_validation_config=$temporary_directory/ghostty-config.ghostty
  cp -- "$ghostty_appearance" "$ghostty_validation_profile"
  sed "s|config-file = /home/tristan/.config/ghostty/profile.ghostty|config-file = $ghostty_validation_profile|" \
    "$ghostty_config" > "$ghostty_validation_config"
fi
"$system_closure/sw/bin/ghostty" +validate-config \
  --config-file="$ghostty_validation_config"
grep -qF 'background = #0B0D0C' "$ghostty_appearance"
grep -qF 'palette = 2=#67B87A' "$ghostty_appearance"

grep -qF 'initial-command = direct:/run/current-system/sw/bin/bash' "$ghostty_config"
grep -qF 'command = direct:/run/current-system/sw/bin/ghostty-surface-shell' "$ghostty_config"
grep -qF 'shell-integration = bash' "$ghostty_config"
grep -qF 'shell-integration-features = ssh-env' "$ghostty_config"
for ghostty_helper in ghostty-profile ghostty-surface-profile ghostty-surface-shell; do
  [[ -x $system_closure/sw/bin/$ghostty_helper ]]
done
[[ ! -e $system_closure/sw/bin/ghostty-split-profile ]]
ghostty_profile_launcher=$system_closure/sw/share/applications/ghostty-profile.desktop
[[ -r $ghostty_profile_launcher ]]
grep -qF 'X-KDE-Shortcuts=Meta+Shift+Return' "$ghostty_profile_launcher"
if grep -qF 'ghostty-split-profile' "$hyprland_config"; then
  printf 'The Hyprland-only Ghostty split hook is still configured.\n' >&2
  exit 1
fi

printf 'Checking ckb-next in the built default system...\n'
[[ -x $system_closure/sw/bin/ckb-next ]]
[[ -x $system_closure/sw/bin/ckb-next-daemon ]]
[[ -r $system_closure/etc/systemd/system/ckb-next.service ]]
ckb_daemon=$(readlink -f "$system_closure/sw/bin/ckb-next-daemon")
ckb_package=${ckb_daemon%/bin/ckb-next-daemon}
[[ -r $ckb_package/lib/udev/rules.d/99-ckb-next-daemon.rules ]]

