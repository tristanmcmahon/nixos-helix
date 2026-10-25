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
require_closure_commands "$theme_helper" gsettings python3 plasma-apply-colorscheme \
  plasma-apply-desktoptheme plasma-apply-cursortheme plasma-apply-wallpaperimage \
  kwriteconfig6 install
# Each login applies exactly one theme, from the session's rotation.
[[ ! -e $system_closure/etc/systemd/user/helix-graphite-fern-theme.service ]]
[[ -r $system_closure/etc/systemd/user/helix-ghostty-config.service ]]
for theme_asset in gtk-3.0-settings.ini gtk-4.0-settings.ini \
  fuzzel.ini steam.css wallpaper.svg apply-theme-settings.py; do
  [[ -r $system_closure/etc/helix/theme/$theme_asset ]]
done
for theme in fern petrol plum oxide amber rosewood hotdog; do
  [[ -r $system_closure/etc/helix/themes/$theme/zed.json ]]
done
helix_theme=$system_closure/sw/bin/helix-theme
require_contains "$helix_theme" 'apply-theme-settings.py merge-zed'
[[ -x $system_closure/sw/bin/adwaita-steam-gtk ]]
[[ -x $system_closure/sw/bin/helix-apply-steam-theme ]]
"$system_closure/sw/bin/helix-apply-steam-theme" --help | grep -qF 'Close Steam first'
grep -qF -- '--adw-accent-rgb: 103, 184, 122' "$system_closure/etc/helix/theme/steam.css"
[[ -r $system_closure/sw/share/themes/Breeze-Dark/settings.ini ]]
[[ -r $system_closure/sw/share/icons/breeze-dark/index.theme ]]
# The login theme script also enforces Plasma's performance baseline every
# login: no compositor eye-candy, no splash, tearing allowed for fullscreen
# games, and Baloo's file indexer disabled.
# A missing gsettings-desktop-schemas must not take the whole KDE block above
# down with it under set -e (incident: app-helix-theme@autostart.service
# failed every login from 2026-09-27 to 2026-10-20).
require_contains "$helix_theme" 'gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true'
require_contains "$helix_theme" 'kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0'
require_contains "$helix_theme" 'kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false'
require_contains "$helix_theme" 'kwriteconfig6 --file kwinrc --group Compositing --key AllowTearing true'
require_contains "$helix_theme" 'balooctl6 disable'
# Validate the managed Ghostty config with every built profile it may include,
# substituting a temporary path for the per-user profile file.
ghostty_validation_profile=$temporary_directory/ghostty-profile.ghostty
ghostty_validation_config=$temporary_directory/ghostty-config.ghostty
sed "s|^config-file = .*|config-file = $ghostty_validation_profile|" \
  config/ghostty/config.ghostty > "$ghostty_validation_config"
grep -qxF "config-file = $ghostty_validation_profile" "$ghostty_validation_config"
ghostty_profile_count=0
for ghostty_profile in "$system_closure"/etc/helix/ghostty/profiles/*.ghostty; do
  # Store files are read-only; install gives the copy a writable mode so the
  # next profile can replace it.
  install -m 0644 -- "$ghostty_profile" "$ghostty_validation_profile"
  "$system_closure/sw/bin/ghostty" +validate-config \
    --config-file="$ghostty_validation_config"
  ghostty_profile_count=$((ghostty_profile_count + 1))
done
((ghostty_profile_count == 8))
for ghostty_helper in ghostty-profile ghostty-surface-profile ghostty-surface-shell ghostty-theme; do
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

