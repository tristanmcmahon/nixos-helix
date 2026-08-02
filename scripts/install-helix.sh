#!/usr/bin/env bash

set -euo pipefail

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

phase() {
  printf '\n===== %s =====\n' "$1"
}

require_line() {
  local file=$1
  local pattern=$2
  local description=$3

  grep -Eq -- "$pattern" "$file" || die "$description is not set as expected in $file."
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

phase 'Repository'
printf 'Repository: %s\n' "$repo_root"
printf 'Branch: %s\n' "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || printf '(detached HEAD)')"
printf 'Commit: %s\n' "$(git rev-parse HEAD)"

phase 'Git safety checks'
if [[ -n $(git status --short) ]]; then
  printf 'The working tree is not clean:\n' >&2
  git status --short >&2
  die 'Commit or otherwise resolve local changes before installing; nothing was changed automatically.'
fi
git remote get-url origin >/dev/null 2>&1 || die "This checkout does not have an 'origin' remote."

phase 'Update main'
git switch main
git pull --ff-only origin main
printf 'Updated commit: %s\n' "$(git rev-parse HEAD)"

phase 'Helix safeguards'
[[ -s hardware-configuration.nix ]] || die 'hardware-configuration.nix is missing or empty.'
git ls-files --error-unmatch hardware-configuration.nix >/dev/null 2>&1 ||
  die 'hardware-configuration.nix is not tracked by Git.'
[[ -x scripts/check.sh ]] || die 'scripts/check.sh is missing or not executable.'
[[ -x scripts/rebuild.sh ]] || die 'scripts/rebuild.sh is missing or not executable.'

require_line configuration.nix \
  '^[[:space:]]*system\.stateVersion[[:space:]]*=[[:space:]]*"25\.11"[[:space:]]*;[[:space:]]*$' \
  'system.stateVersion = "25.11"'
require_line system/boot.nix \
  '^[[:space:]]*boot\.loader\.systemd-boot\.enable[[:space:]]*=[[:space:]]*true[[:space:]]*;[[:space:]]*$' \
  'systemd-boot'
require_line system/boot.nix \
  '^[[:space:]]*boot\.loader\.efi\.canTouchEfiVariables[[:space:]]*=[[:space:]]*true[[:space:]]*;[[:space:]]*$' \
  'EFI variable access'
require_line desktop/plasma.nix \
  '^[[:space:]]*services\.desktopManager\.plasma6\.enable[[:space:]]*=[[:space:]]*true[[:space:]]*;[[:space:]]*$' \
  'Plasma 6'
require_line desktop/plasma.nix \
  '^[[:space:]]*services\.displayManager\.sddm\.enable[[:space:]]*=[[:space:]]*true[[:space:]]*;[[:space:]]*$' \
  'SDDM'
require_line hardware/nvidia.nix \
  '^[[:space:]]*open[[:space:]]*=[[:space:]]*true[[:space:]]*;[[:space:]]*$' \
  'hardware.nvidia.open = true'

if while IFS= read -r nix_file; do
  sed 's/#.*$//' "$nix_file"
done < <(git ls-files '*.nix' ':!hardware-configuration.nix') |
  grep -Eq 'hardware\.nvidia\.branch[[:space:]]*='; then
  die 'An active hardware.nvidia.branch option exists in a maintained Nix file.'
fi

printf 'Evaluating merged NixOS safeguards...\n'
nix-instantiate --eval --strict -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
    config = system.config;
  in
  assert config.system.stateVersion == "25.11";
  assert config.boot.loader.systemd-boot.enable;
  assert config.boot.loader.efi.canTouchEfiVariables;
  assert config.services.desktopManager.plasma6.enable;
  assert config.services.displayManager.sddm.enable;
  assert config.hardware.nvidia.open;
  true
'

phase 'Complete validation suite'
nix-shell --run './scripts/check.sh'

phase 'Pending installation'
printf '%s\n' \
  'The Helix configuration will:' \
  '  - keep Plasma 6 as the primary SDDM desktop' \
  '  - add Hyprland as an optional SDDM login session' \
  '  - install Vim/vi as the console recovery editor' \
  '  - enable the declarative modern-bash shell environment' \
  '  - enable ckb-next support for the Corsair K70 RGB' \
  '  - install workstation tools' \
  '  - install media applications, Plex Desktop, and GridPlayer' \
  '  - install the 1Password desktop application and CLI' \
  '  - deploy browser extension policies and prepare optional SSH-agent use' \
  '  - apply Helix Abyss to Plasma, applications, and the login screen' \
  '  - deploy dark browser policy with official Dark Reader' \
  '  - style the optional Hyprland session, Waybar, Mako, and Fuzzel' \
  '  - install development tools' \
  '  - install VS Code' \
  '  - install the OpenAI Codex CLI' \
  '  - install GitHub CLI and Git LFS' \
  '  - enable the nightly 02:00 generation cleanup timer' \
  '  - retain the active system plus two additional generations' \
  '  - enable gaming with Steam, GameMode, and MangoHud' \
  '  - enable 32-bit graphics and audio support for gaming' \
  '  - leave local LLM disabled'

printf 'Install the Helix configuration now? [y/N] '
if ! IFS= read -r install_answer; then
  printf '\nNo input received; installation cancelled.\n'
  exit 0
fi
case $install_answer in
y | Y | yes | YES) ;;
*)
  printf 'Installation cancelled; no configuration was activated.\n'
  exit 0
  ;;
esac

phase 'Persistent activation'
./scripts/rebuild.sh switch

phase 'Installed-result verification'
sddm_enabled=$(nix-instantiate --eval --strict -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in
  system.config.services.displayManager.sddm.enable
') || die 'Could not evaluate the configured SDDM state after activation.'
[[ $sddm_enabled == true ]] || die 'The repository configuration does not enable SDDM.'

configured_display_manager=$(nix-instantiate --eval --raw -E '
  let
    system = import <nixpkgs/nixos> { configuration = ./configuration.nix; };
  in
  system.config.services.displayManager.execCmd
') || die 'Could not evaluate the configured display-manager executable.'
display_manager_unit=$(systemctl cat display-manager.service) ||
  die 'Could not inspect display-manager.service.'
display_manager_exec=$(systemctl show display-manager.service --property=ExecStart --value) ||
  die 'Could not inspect the display-manager.service executable.'
printf '%s\n' "$display_manager_unit"
printf 'ExecStart: %s\n' "$display_manager_exec"
printf 'Configured display manager: %s\n' "$configured_display_manager"

display_manager_evidence="$display_manager_unit
$display_manager_exec"
exec_start_path=$(sed -n 's/.*path=\([^ ;}]*\).*/\1/p' <<<"$display_manager_exec" | head -n 1)
if [[ -n $exec_start_path && -r $exec_start_path ]]; then
  display_manager_evidence+=$'\n'
  display_manager_evidence+=$(<"$exec_start_path")
fi
grep -Eiq 'sddm' <<<"$display_manager_evidence" ||
  die 'display-manager.service does not reference SDDM or its configured executable.'

systemctl is-enabled helix-nix-cleanup.timer ||
  die 'helix-nix-cleanup.timer is not enabled after activation.'
export PATH="/run/current-system/sw/bin:$PATH"
command -v vi >/dev/null || die 'vi is not available in PATH after activation.'
command -v vim >/dev/null || die 'vim is not available in PATH after activation.'
command -v code >/dev/null || die 'code is not available in PATH after activation.'
command -v codex >/dev/null || die 'codex is not available in PATH after activation.'
command -v gh >/dev/null || die 'gh is not available in PATH after activation.'
if command -v git-lfs >/dev/null; then
  git-lfs version
else
  git lfs version || die 'Git LFS is not working after activation.'
fi
systemctl list-timers --all | grep 'helix-nix-cleanup.timer' ||
  die 'helix-nix-cleanup.timer is absent from the system timer list.'

printf '\nInstalled tool versions:\n'
code --version
codex --version
gh --version
git lfs version

phase 'Reboot'
printf 'Reboot into Plasma now? [Y/n] '
if ! IFS= read -r reboot_answer; then
  reboot_answer=''
  printf '\n'
fi
case $reboot_answer in
n | N | no | NO)
  printf 'Reboot later with:\n  sudo reboot\n'
  ;;
*)
  sudo reboot
  ;;
esac
