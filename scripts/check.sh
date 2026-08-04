#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

printf 'Checking Nix formatting...\n'
temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT

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

printf 'Running ShellCheck...\n'
shellcheck scripts/*.sh

printf 'Checking Nix dead code and lint...\n'
deadnix --fail .
statix check .

printf 'Checking Git whitespace...\n'
git diff --check

printf 'Checking documentation links and tracked secrets...\n'
python3 scripts/check-docs.py
if git ls-files | grep -Eq '(^|/)(id_(rsa|dsa|ecdsa|ed25519)|.*credentials.*|infernalnexus-smb)$'; then
  printf 'A credential or private-key-shaped file is tracked.\n' >&2
  exit 1
fi
if git grep -Il '' -- ':!.git' | xargs grep -El \
  -- '-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}' >/dev/null; then
  printf 'A private key or token-shaped value is present in tracked content.\n' >&2
  exit 1
fi

printf 'Validating Helix Abyss assets and merge fixtures...\n'
python3 scripts/test-theme-settings.py

printf 'Testing generation-cleanup planning...\n'
cleanup_program=$(nix-build --no-out-link -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    matches = builtins.filter
      (package: (package.name or "") == "helix-nix-cleanup")
      system.config.environment.systemPackages;
  in
  builtins.head matches
')
./scripts/test-cleanup-plan.sh "$cleanup_program/bin/helix-nix-cleanup"

printf 'Evaluating release, desktop, security, and native NAS invariants...\n'
nix-instantiate --eval --strict -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    config = system.config;
    release = import ./release.nix;
    packageNames = map
      (package: package.pname or package.name or "")
      config.environment.systemPackages;
    infernalnexusMounts = builtins.filter
      (mount: mount.where == "/mnt/infernalnexus/nas1") config.systemd.mounts;
    infernalnexusAutomounts = builtins.filter
      (automount: automount.where == "/mnt/infernalnexus/nas1") config.systemd.automounts;
    infernalnexusMount = builtins.head infernalnexusMounts;
    infernalnexusAutomount = builtins.head infernalnexusAutomounts;
    infernalnexusOptions = builtins.filter builtins.isString
      (builtins.split "," infernalnexusMount.options);
  in
  assert config.system.nixos.release == release.nixosRelease;
  assert config.system.stateVersion == release.stateVersion;
  assert config.services.desktopManager.plasma6.enable;
  assert config.services.displayManager.sddm.enable;
  assert config.programs.hyprland.enable;
  assert config.programs.hyprland.withUWSM;
  assert config.programs.steam.enable;
  assert config.programs.gamemode.enable;
  assert !config.services.ollama.enable;
  assert config.hardware.ckb-next.enable;
  assert config.services.openssh.enable;
  assert config.services.openssh.openFirewall;
  assert config.services.openssh.ports == [ 22 ];
  assert config.services.openssh.settings.PermitRootLogin == "no";
  assert config.services.openssh.settings.PubkeyAuthentication;
  assert !config.services.openssh.settings.PasswordAuthentication;
  assert !config.services.openssh.settings.KbdInteractiveAuthentication;
  assert config.networking.hosts."192.168.1.2" == [ "mister" ];
  assert config.networking.hosts."192.168.1.8" == [ "infernalnexus" ];
  assert !(builtins.hasAttr "/mnt/infernalnexus/nas1" config.fileSystems);
  assert builtins.length infernalnexusMounts == 1;
  assert infernalnexusMount.what == "//192.168.1.8/nas1";
  assert infernalnexusMount.type == "cifs";
  assert builtins.all (option: builtins.elem option infernalnexusOptions) [
    "credentials=/etc/nixos/secrets/infernalnexus-smb"
    "uid=tristan"
    "gid=users"
    "dir_mode=0775"
    "file_mode=0664"
  ];
  assert builtins.elem "vers=2.0" infernalnexusOptions;
  assert builtins.elem "sec=ntlmssp" infernalnexusOptions;
  assert !(builtins.elem "vers=1.0" infernalnexusOptions);
  assert !(builtins.elem "x-systemd.automount" infernalnexusOptions);
  assert builtins.all
    (option: builtins.match "x-systemd\\.(mount-timeout|idle-timeout).*" option == null)
    infernalnexusOptions;
  assert builtins.elem "network-online.target" infernalnexusMount.wants;
  assert builtins.elem "network-online.target" infernalnexusMount.after;
  assert infernalnexusMount.mountConfig.TimeoutSec == "15s";
  assert builtins.length infernalnexusAutomounts == 1;
  assert builtins.elem "multi-user.target" infernalnexusAutomount.wantedBy;
  assert infernalnexusAutomount.automountConfig.TimeoutIdleSec == "10min";
  assert builtins.elem 22 config.networking.firewall.allowedTCPPorts;
  assert builtins.hasAttr "sshd" config.systemd.services;
  assert config.programs._1password.enable;
  assert config.programs._1password-gui.enable;
  assert config.programs._1password-gui.polkitPolicyOwners == [ "tristan" ];
  assert config.programs.chromium.enable;
  assert config.programs.chromium.extensions == [
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    "eimadpbcbfnmbkopoojfekhnkhdbieeh"
  ];
  assert config.programs.chromium.extraOpts.BrowserThemeColor == "#030405";
  assert !config.programs.chromium.extraOpts.PasswordManagerEnabled;
  assert config.programs.firefox.enable;
  assert !config.programs.firefox.policies.OfferToSaveLogins;
  assert builtins.hasAttr "addon@darkreader.org" config.programs.firefox.policies.ExtensionSettings;
  assert config.programs.firefox.preferences."ui.systemUsesDarkTheme" == 1;
  assert config.services.displayManager.sddm.theme == "helix-abyss";
  assert config.programs.dconf.enable;
  assert config.systemd.user.services.helix-abyss-theme.unitConfig.ConditionUser == "tristan";
  assert config.systemd.user.services.helix-ghostty-config.unitConfig.ConditionUser == "tristan";
  assert builtins.elem "HOME=/home/tristan"
    config.systemd.user.services.helix-ghostty-config.serviceConfig.Environment;
  assert builtins.elem "XDG_CONFIG_HOME=/home/tristan/.config"
    config.systemd.user.services.helix-ghostty-config.serviceConfig.Environment;
  assert !(builtins.hasAttr "GTK_THEME" config.environment.variables);
  assert !(builtins.hasAttr "QT_STYLE_OVERRIDE" config.environment.variables);
  assert !(builtins.hasAttr "QT_QPA_PLATFORMTHEME" config.environment.variables);
  assert builtins.all
    (name: builtins.elem name packageNames)
    [ "spotify" "vlc" "haruna" "strawberry" "plex-desktop" "gridplayer" ];
  assert builtins.any (name: builtins.match "mpv.*" name != null) packageNames;
  assert !(builtins.elem "plexmediaserver" packageNames);
  assert builtins.hasAttr "ckb-next" config.systemd.services;
  assert config.environment.variables.EDITOR == "vim";
  assert config.environment.variables.VISUAL == "vim";
  assert builtins.any (name: builtins.match "vim.*" name != null) packageNames;
  true
'

corsair_imports=$(grep -cF './hardware/corsair-k70.nix' configuration.nix)
[[ $corsair_imports -eq 1 ]] || {
  printf 'Expected exactly one Corsair module import, found %s.\n' "$corsair_imports" >&2
  exit 1
}

hosts_imports=$(grep -cF './system/hosts.nix' configuration.nix)
[[ $hosts_imports -eq 1 ]] || {
  printf 'Expected exactly one static-hosts module import, found %s.\n' "$hosts_imports" >&2
  exit 1
}

openssh_imports=$(grep -cF './services/openssh.nix' configuration.nix)
[[ $openssh_imports -eq 1 ]] || {
  printf 'Expected exactly one OpenSSH module import, found %s.\n' "$openssh_imports" >&2
  exit 1
}

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
  system.config.services.displayManager.execCmd
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

printf 'Checking Helix Abyss in the built default system...\n'
[[ -r $system_closure/sw/share/color-schemes/HelixAbyss.colors ]]
QT_QPA_PLATFORM=offscreen XDG_DATA_DIRS="$system_closure/sw/share" \
  "$system_closure/sw/bin/plasma-apply-colorscheme" --list-schemes |
  grep -qF 'HelixAbyss'
[[ -r $system_closure/sw/share/wallpapers/HelixAbyss/contents/images/wallpaper.svg ]]
[[ -r $system_closure/sw/share/sddm/themes/helix-abyss/theme.conf ]]
grep -qF 'HelixAbyss/contents/images/wallpaper.svg' \
  "$system_closure/sw/share/sddm/themes/helix-abyss/theme.conf"
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
theme_unit=$system_closure/etc/systemd/user/helix-abyss-theme.service
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
  fuzzel.ini wallpaper.svg apply-theme-settings.py; do
  [[ -r $system_closure/etc/helix/theme/$theme_asset ]]
done
[[ -r $system_closure/sw/share/themes/Breeze-Dark/settings.ini ]]
[[ -r $system_closure/sw/share/icons/breeze-dark/index.theme ]]
grep -qF 'swaybg --image /etc/helix/theme/wallpaper.svg' "$hyprland_config"
grep -qF 'waybar --style /etc/helix/theme/waybar.css' "$hyprland_config"
grep -qF 'mako --config /etc/helix/theme/mako.conf' "$hyprland_config"
grep -qF 'fuzzel --config /etc/helix/theme/fuzzel.ini' "$hyprland_config"
"$system_closure/sw/bin/ghostty" +validate-config \
  --config-file=config/ghostty/config.ghostty
grep -qF 'theme = Catppuccin Mocha' config/ghostty/config.ghostty
vscode_executable=$(readlink -f "$system_closure/sw/bin/code")
vscode_package=${vscode_executable%%/bin/*}
find "$vscode_package" -path '*/theme-abyss/package.json' -print -quit | grep -q .

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
    -h "$sshd_test_key" 2>/dev/null
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

printf 'Dry-building local-LLM profile...\n'
./scripts/check-profile.sh local-llm
