#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "$repo_root/scripts/release-environment.sh"
cd "$repo_root"

required_tools=(deadnix nixfmt shellcheck statix)
for required_tool in "${required_tools[@]}"; do
  if ! command -v "$required_tool" >/dev/null; then
    printf 'Missing validation tool: %s\n' "$required_tool" >&2
    printf "Run: ./scripts/dev-shell.sh --run './scripts/check.sh'\n" >&2
    exit 1
  fi
done

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT

printf 'Checking deterministic release selection...\n'
expected_release=$(nix-instantiate --eval --raw -E '(import ./release.nix).nixosRelease')
selected_nixpkgs=$HELIX_SELECTED_NIXPKGS
release_selection=$(
  NIX_PATH=/deliberately/invalid \
    HELIX_NIXPKGS_PATH="$selected_nixpkgs" \
    bash -c 'source "$1" >/dev/null; printf "%s|%s|%s\n" "$HELIX_SELECTED_RELEASE" "$HELIX_SELECTED_NIXPKGS" "$NIX_PATH"' \
    _ "$repo_root/scripts/release-environment.sh"
)
[[ $release_selection == "$expected_release|$selected_nixpkgs|nixpkgs=$selected_nixpkgs:nixos-config=$repo_root/configuration.nix:$selected_nixpkgs" ]]

# Model the graphical installer: an explicit readable tree must work even when
# no root channel is involved. The symlink also proves canonicalisation.
ln -s -- "$selected_nixpkgs" "$temporary_directory/explicit-nixpkgs"
explicit_selection=$(
  NIX_PATH=/deliberately/invalid \
    HELIX_NIXPKGS_PATH="$temporary_directory/explicit-nixpkgs" \
    bash -c 'source "$1" >/dev/null; printf "%s|%s\n" "$HELIX_SELECTED_RELEASE" "$HELIX_SELECTED_NIXPKGS"' \
    _ "$repo_root/scripts/release-environment.sh"
)
[[ $explicit_selection == "$expected_release|$selected_nixpkgs" ]]
if HELIX_NIXPKGS_PATH=/deliberately/missing \
  bash -c 'source "$1"' _ "$repo_root/scripts/release-environment.sh" >/dev/null 2>&1; then
  printf 'release-environment accepted an unreadable explicit Nixpkgs source.\n' >&2
  exit 1
fi
root_channel=/nix/var/nix/profiles/per-user/root/channels/nixos
if [[ -r $root_channel/default.nix ]]; then
  root_selection=$(
    NIX_PATH=/deliberately/invalid bash -c \
      'unset HELIX_NIXPKGS_PATH; source "$1" >/dev/null; printf "%s|%s\n" "$HELIX_SELECTED_RELEASE" "$HELIX_SELECTED_NIXPKGS"' \
      _ "$repo_root/scripts/release-environment.sh"
  )
  [[ $root_selection == "$expected_release|$(readlink -f "$root_channel")" ]]
fi

printf 'Checking Nix formatting...\n'
PYTHONPYCACHEPREFIX=$temporary_directory \
  python3 -m py_compile scripts/*.py

while IFS= read -r nix_file; do
  temporary_file="$temporary_directory/${nix_file//\//_}"
  cp -- "$nix_file" "$temporary_file"
  nixfmt "$temporary_file"
  if ! cmp -s -- "$nix_file" "$temporary_file"; then
    printf 'Formatting required: %s\n' "$nix_file" >&2
    diff -u -- "$nix_file" "$temporary_file" || true
    exit 1
  fi
done < <(find . -name '*.nix' -type f ! -name hardware-configuration.nix -print | sort)

printf 'Checking shell syntax...\n'
bash -n scripts/*.sh

if grep -Eq '\b(mkfs|parted|fdisk|sgdisk|wipefs|mount|umount|swapon|swapoff|mkswap|e2label|fatlabel)\b' \
  scripts/backup-for-reinstall.sh scripts/reinstall-preflight.sh \
  scripts/reinstall-postflight.sh scripts/restore-after-reinstall.sh \
  scripts/check-install-storage.sh; then
  printf 'A destructive storage command entered a read-only reinstall helper.\n' >&2
  exit 1
fi

printf 'Running ShellCheck...\n'
shellcheck scripts/*.sh

printf 'Checking Nix dead code and lint...\n'
deadnix --fail --exclude hardware-configuration.nix -- .
statix check . -i hardware-configuration.nix

printf 'Checking Git whitespace...\n'
git diff --check

printf 'Checking documentation links and tracked secrets...\n'
python3 scripts/check-docs.py
python3 scripts/check-modules.py
if git ls-files | grep -Eq '(^|/)(id_(rsa|dsa|ecdsa|ed25519)|.*credentials.*|infernalnexus-smb)$'; then
  printf 'A credential or private-key-shaped file is tracked.\n' >&2
  exit 1
fi
if git ls-files | grep -Ei \
  '(^|/)(COMPLETE|SHA256SUMS|.*\.(tar|tar\.(gz|xz|zst)|tgz|zip|7z))$'; then
  printf 'A backup marker, checksum manifest, or archive-shaped file is tracked.\n' >&2
  exit 1
fi
if git grep -Il '' -- ':!.git' | xargs grep -El \
  -- '-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}' >/dev/null; then
  printf 'A private key or token-shaped value is present in tracked content.\n' >&2
  exit 1
fi

printf 'Validating Helix Graphite + Fern assets and merge fixtures...\n'
python3 scripts/test-theme-settings.py

./scripts/test-reinstall-safety.sh
./scripts/test-reinstall-restore.sh

printf 'Evaluating release, storage, desktop, and security invariants...\n'
nix-instantiate --eval --strict tests/system-invariants.nix

printf 'Building the complete default system closure...\n'
system_closure=$(nix-build --no-out-link '<nixpkgs/nixos>' -A system \
  -I "nixos-config=$repo_root/configuration.nix")

printf 'Checking Vim and modern-bash in the built default system...\n'
./scripts/test-modern-bash.sh "$system_closure"

printf 'Verifying the repository-owned Hyprland baseline...\n'
hyprland_config=$(nix-build --no-out-link -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.environment.etc."hypr/helix.conf".source
')
"$system_closure/sw/bin/Hyprland" --verify-config --config "$hyprland_config"
polkit_agent=$(sed -n 's/^exec-once = \(.*polkit-kde-authentication-agent-1\)$/\1/p' "$hyprland_config")
[[ -x $polkit_agent ]]

printf 'Checking generated display-manager sessions...\n'
configured_display_manager=$(nix-instantiate --eval --raw -E '
  let
    system = import <nixpkgs/nixos> {
      configuration = ./configuration.nix;
    };
  in
  system.config.services.displayManager.generic.execCmd
')
[[ -n $configured_display_manager ]]
grep -qi 'sddm' <<<"$configured_display_manager"

session_data=$(nix-build --no-out-link -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.services.displayManager.sessionData.desktops
')
find "$session_data/share" -type f -name '*.desktop' -print
grep -Rqs '^Name=Plasma' "$session_data/share/wayland-sessions"
grep -Rqs '^Name=Hyprland' "$session_data/share/wayland-sessions"

printf 'Checking Helix Graphite + Fern in the built default system...\n'
[[ -r $system_closure/sw/share/color-schemes/HelixGraphiteFern.colors ]]
QT_QPA_PLATFORM=offscreen XDG_DATA_DIRS="$system_closure/sw/share" \
  "$system_closure/sw/bin/plasma-apply-colorscheme" --list-schemes |
  grep -qF 'HelixGraphiteFern'
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
grep -qF 'swaybg --image /etc/helix/theme/wallpaper.svg' "$hyprland_config"
grep -qF 'waybar --style /etc/helix/theme/waybar.css' "$hyprland_config"
grep -qF 'mako --config /etc/helix/theme/mako.conf' "$hyprland_config"
grep -qF 'fuzzel --config /etc/helix/theme/fuzzel.ini' "$hyprland_config"
"$system_closure/sw/bin/ghostty" +validate-config \
  --config-file=config/ghostty/config.ghostty
grep -qF 'background = #0B0D0C' config/ghostty/config.ghostty
grep -qF 'palette = 2=#67B87A' config/ghostty/config.ghostty

printf 'Checking ckb-next in the built default system...\n'
[[ -x $system_closure/sw/bin/ckb-next ]]
[[ -x $system_closure/sw/bin/ckb-next-daemon ]]
[[ -r $system_closure/etc/systemd/system/ckb-next.service ]]
ckb_daemon=$(readlink -f "$system_closure/sw/bin/ckb-next-daemon")
ckb_package=${ckb_daemon%/bin/ckb-next-daemon}
[[ -r $ckb_package/lib/udev/rules.d/99-ckb-next-daemon.rules ]]

printf 'Checking OpenSSH in the built default system...\n'
[[ -r $system_closure/etc/systemd/system/sshd.service ]]
sshd_test_key=$temporary_directory/ssh_host_ed25519_key
"$system_closure/sw/bin/ssh-keygen" -q -t ed25519 -N '' -f "$sshd_test_key"
sshd_effective=$(
  "$system_closure/sw/bin/sshd" -T \
    -f "$system_closure/etc/ssh/sshd_config" \
    -h "$sshd_test_key" 2>/dev/null | tr '[:upper:]' '[:lower:]'
)
for ssh_setting in \
  'permitrootlogin no' \
  'pubkeyauthentication yes' \
  'passwordauthentication no' \
  'kbdinteractiveauthentication no'; do
  grep -qxF "$ssh_setting" <<<"$sshd_effective"
done

printf 'Checking static native Infernalnexus units...\n'
nas_mount_unit=$system_closure/etc/systemd/system/mnt-infernalnexus-nas1.mount
nas_automount_unit=$system_closure/etc/systemd/system/mnt-infernalnexus-nas1.automount
[[ -r $nas_mount_unit ]]
[[ -r $nas_automount_unit ]]
[[ -L $system_closure/etc/systemd/system/multi-user.target.wants/mnt-infernalnexus-nas1.automount ]]
grep -qF 'What=//192.168.1.8/nas1' "$nas_mount_unit"
grep -qF 'Where=/mnt/infernalnexus/nas1' "$nas_mount_unit"
grep -qF 'Type=cifs' "$nas_mount_unit"
grep -qF 'Options=' "$nas_mount_unit"
grep -qF 'TimeoutSec=15s' "$nas_mount_unit"
grep -qF 'TimeoutIdleSec=10min' "$nas_automount_unit"
if grep -Eq '//192\.168\.1\.8/nas1|/mnt/infernalnexus/nas1|x-systemd\.automount' \
  "$system_closure/etc/fstab"; then
  printf 'Infernalnexus still appears in generated fstab.\n' >&2
  exit 1
fi
"$system_closure/sw/bin/systemd-analyze" verify "$nas_mount_unit" "$nas_automount_unit"

printf 'Checking media applications in the built default system...\n'
for media_executable in spotify vlc mpv haruna strawberry plex-desktop gridplayer; do
  [[ -x $system_closure/sw/bin/$media_executable ]]
done
for desktop_pattern in 'Spotify' 'VLC media player' 'Haruna' 'Strawberry' 'Plex' 'GridPlayer'; do
  grep -Rqs "^Name=.*$desktop_pattern" "$system_closure/sw/share/applications"
done
[[ -r $system_closure/sw/share/icons/hicolor/scalable/apps/gridplayer.svg ]]
gridplayer_wrapper=$(readlink -f "$system_closure/sw/bin/gridplayer")
grep -Eq '/nix/store/[^/]+-vlc-[^/]+/lib' "$gridplayer_wrapper"

printf 'Checking messaging applications and local inference in the built default system...\n'
for application_executable in signal-desktop pidgin; do
  [[ -x $system_closure/sw/bin/$application_executable ]]
done
for desktop_pattern in 'Signal' 'Pidgin'; do
  grep -Rqs "^Name=.*$desktop_pattern" "$system_closure/sw/share/applications"
done
if find "$system_closure/etc/xdg/autostart" "$system_closure/sw/share/autostart" \
  -type f \( -iname '*signal*' -o -iname '*pidgin*' \) -print -quit 2>/dev/null | grep -q .; then
  printf 'Signal or Pidgin is configured to autostart.\n' >&2
  exit 1
fi
[[ -x $system_closure/sw/bin/ollama ]]
[[ -x $system_closure/sw/bin/helix-ollama-update-models ]]
[[ -r $system_closure/etc/systemd/system/ollama.service ]]
[[ -r $system_closure/etc/systemd/system/ollama-model-loader.service ]]
grep -qF 'OLLAMA_HOST=127.0.0.1:11434' \
  "$system_closure/etc/systemd/system/ollama.service"
grep -qF 'BindsTo=ollama.service' \
  "$system_closure/etc/systemd/system/ollama-model-loader.service"
for model in deepseek-r1:8b gemma4:12b gpt-oss:20b qwen3.6:27b qwen3-embedding:4b; do
  grep -qF "$model" "$system_closure/sw/bin/helix-ollama-update-models"
done
[[ -x $system_closure/sw/bin/chatgpt ]]
grep -Rqs '^Name=ChatGPT$' "$system_closure/sw/share/applications"

printf 'Checking 1Password modules, wrappers, and browser policies...\n'
onepassword_gui=$(nix-build --no-out-link -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.programs._1password-gui.package
')
onepassword_cli=$(nix-build --no-out-link -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.programs._1password.package
')
[[ -x $onepassword_cli/bin/op ]]
[[ -x $onepassword_gui/bin/1password ]]
[[ -x $onepassword_gui/share/1password/1Password-BrowserSupport ]]
find "$onepassword_gui/share/applications" -type f -name '*.desktop' | grep -q .
[[ -n $(nix-instantiate --eval --raw -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.security.wrappers.op.source
') ]]
[[ -n $(nix-instantiate --eval --raw -E '
  let system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in system.config.security.wrappers."1Password-BrowserSupport".source
') ]]
[[ -r $system_closure/etc/chromium/policies/managed/default.json ]]
[[ -r $system_closure/etc/opt/chrome/policies/managed/default.json ]]
grep -qF 'aeblfdkhhhdcdjpifhhbdiojplfjncoa' "$system_closure/etc/chromium/policies/managed/default.json"
grep -qF 'aeblfdkhhhdcdjpifhhbdiojplfjncoa' "$system_closure/etc/opt/chrome/policies/managed/default.json"
grep -qF 'eimadpbcbfnmbkopoojfekhnkhdbieeh' "$system_closure/etc/chromium/policies/managed/default.json"
grep -qF 'eimadpbcbfnmbkopoojfekhnkhdbieeh' "$system_closure/etc/opt/chrome/policies/managed/default.json"
firefox_policy=$system_closure/etc/firefox/policies/policies.json
[[ -r $firefox_policy ]]
grep -qF '{d634138d-c276-4fc8-924b-40a0ea21d284}' "$firefox_policy"
grep -qF 'addon@darkreader.org' "$firefox_policy"
grep -qxF 'zen-bin' "$system_closure/etc/1password/custom_allowed_browsers"
if git diff -- . ':(exclude)scripts/check.sh' |
  grep -Eq 'OP_SERVICE_ACCOUNT_TOKEN[[:space:]]*=|OP_SESSION_[A-Za-z0-9_]*[[:space:]]='; then
  printf 'A forbidden 1Password secret or sign-in pattern entered the diff.\n' >&2
  exit 1
fi
