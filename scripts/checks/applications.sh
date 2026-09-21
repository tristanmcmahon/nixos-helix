#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

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
[[ ! -e $system_closure/sw/bin/chatgpt ]]
if grep -Rqs '^Name=ChatGPT$' "$system_closure/sw/share/applications"; then
  printf 'ChatGPT remains in the active system closure.\n' >&2
  exit 1
fi

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
