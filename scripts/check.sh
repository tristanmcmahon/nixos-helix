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

printf 'Checking Git whitespace...\n'
git diff --check

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

printf 'Evaluating editor, desktop, gaming, media, 1Password, and Corsair invariants...\n'
nix-instantiate --eval --strict -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    config = system.config;
    packageNames = map
      (package: package.pname or package.name or "")
      config.environment.systemPackages;
  in
  assert config.services.desktopManager.plasma6.enable;
  assert config.services.displayManager.sddm.enable;
  assert config.programs.hyprland.enable;
  assert config.programs.hyprland.withUWSM;
  assert config.programs.steam.enable;
  assert config.programs.gamemode.enable;
  assert !config.services.ollama.enable;
  assert config.hardware.ckb-next.enable;
  assert config.programs._1password.enable;
  assert config.programs._1password-gui.enable;
  assert config.programs._1password-gui.polkitPolicyOwners == [ "tristan" ];
  assert config.programs.chromium.enable;
  assert config.programs.chromium.extensions == [ "aeblfdkhhhdcdjpifhhbdiojplfjncoa" ];
  assert !config.programs.chromium.extraOpts.PasswordManagerEnabled;
  assert config.programs.firefox.enable;
  assert !config.programs.firefox.policies.OfferToSaveLogins;
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

printf 'Checking ckb-next in the built default system...\n'
[[ -x $system_closure/sw/bin/ckb-next ]]
[[ -x $system_closure/sw/bin/ckb-next-daemon ]]
[[ -r $system_closure/etc/systemd/system/ckb-next.service ]]
ckb_daemon=$(readlink -f "$system_closure/sw/bin/ckb-next-daemon")
ckb_package=${ckb_daemon%/bin/ckb-next-daemon}
[[ -r $ckb_package/lib/udev/rules.d/99-ckb-next-daemon.rules ]]

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
firefox_policy=$system_closure/etc/firefox/policies/policies.json
[[ -r $firefox_policy ]]
grep -qF '{d634138d-c276-4fc8-924b-40a0ea21d284}' "$firefox_policy"
grep -qxF 'zen-bin' "$system_closure/etc/1password/custom_allowed_browsers"
if git diff -- . ':(exclude)scripts/check.sh' |
  grep -Eq 'OP_SERVICE_ACCOUNT_TOKEN[[:space:]]*=|OP_SESSION_[A-Za-z0-9_]*[[:space:]]='; then
  printf 'A forbidden 1Password secret or sign-in pattern entered the diff.\n' >&2
  exit 1
fi

printf 'Dry-building local-LLM profile...\n'
./scripts/check-profile.sh local-llm
