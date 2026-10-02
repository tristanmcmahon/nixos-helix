#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

printf 'Checking helix-update runtime validation tools...\n'
helix_update=$(readlink -f "$system_closure/sw/bin/helix-update")
mapfile -t helix_update_closure < <(nix-store -qR "$helix_update")
for validation_tool in deadnix nixfmt shellcheck statix; do
  found_validation_tool=0
  for closure_path in "${helix_update_closure[@]}"; do
    if [[ -x $closure_path/bin/$validation_tool ]]; then
      found_validation_tool=1
      break
    fi
  done
  if ((!found_validation_tool)); then
    printf 'helix-update runtime is missing validation tool: %s\n' "$validation_tool" >&2
    exit 1
  fi
done

printf 'Checking OpenClaw sandbox in the built default system...\n'
openclaw_unit=$system_closure/etc/systemd/user/openclaw-gateway.service
[[ -r $openclaw_unit ]]
grep -qF '/home/tristan/Projects/nixos-helix' "$openclaw_unit"
grep -qF '/mnt/games_nvme/emulation' "$openclaw_unit"
grep -qF '/mnt/infernalnexus' "$openclaw_unit"
grep -qF 'ProtectSystem=strict' "$openclaw_unit"
grep -qF 'IPAddressDeny=any' "$openclaw_unit"

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

printf 'Checking messaging, agent tooling, and local inference in the built default system...\n'
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
[[ -x $system_closure/sw/bin/claude ]]
[[ -x $system_closure/sw/bin/claude-agent-acp ]]
[[ -x $system_closure/sw/bin/helix-zed-agent-setup ]]
[[ -x $system_closure/sw/bin/ollama ]]
[[ -x $system_closure/sw/bin/helix-ollama-update-models ]]
[[ -r $system_closure/etc/systemd/system/ollama.service ]]
[[ -r $system_closure/etc/systemd/system/ollama-model-loader.service ]]
grep -qF 'BindsTo=ollama.service' \
  "$system_closure/etc/systemd/system/ollama-model-loader.service"
[[ ! -e $system_closure/sw/bin/chatgpt ]]
if grep -Rqs '^Name=ChatGPT$' "$system_closure/sw/share/applications"; then
  printf 'ChatGPT remains in the active system closure.\n' >&2
  exit 1
fi

printf 'Checking 1Password modules, wrappers, and browser policies...\n'
[[ -x $onepassword_cli/bin/op ]]
[[ -x $onepassword_gui/bin/1password ]]
[[ -x $onepassword_gui/share/1password/1Password-BrowserSupport ]]
find "$onepassword_gui/share/applications" -type f -name '*.desktop' | grep -q .
[[ -r $system_closure/etc/chromium/policies/managed/default.json ]]
[[ -r $system_closure/etc/opt/chrome/policies/managed/default.json ]]
[[ -r $system_closure/etc/firefox/policies/policies.json ]]
[[ ! -e $system_closure/etc/1password/custom_allowed_browsers ]]
if git diff -- . ':(exclude)scripts/check.sh' |
  grep -Eq 'OP_SERVICE_ACCOUNT_TOKEN[[:space:]]*=|OP_SESSION_[A-Za-z0-9_]*[[:space:]]='; then
  printf 'A forbidden 1Password secret or sign-in pattern entered the diff.\n' >&2
  exit 1
fi
