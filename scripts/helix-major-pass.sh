#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${HOME}/Projects/nixos-helix"
STAMP="$(date +%Y%m%d-%H%M%S)"
BRANCH="upgrade/helix-major-pass-${STAMP}"
STATE_DIR="${HOME}/.local/state/helix-major-pass/${STAMP}"
PROMPT_FILE="${STATE_DIR}/codex-prompt.txt"
RUN_LOG="${STATE_DIR}/run.log"
SUMMARY_FILE="${STATE_DIR}/summary.txt"

# First-party nix-openclaw packaging revision reviewed on 2026-09-04.
# This revision pins OpenClaw 2026.7.1-2, which is newer than the <2026.6.9
# vulnerable range while avoiding a mutable main/beta package reference.
NIX_OPENCLAW_REV="d3760a6f103642f11e24bc01ee9aec80a0153774"
NIX_OPENCLAW_URL="https://github.com/openclaw/nix-openclaw/archive/${NIX_OPENCLAW_REV}.tar.gz"
EXPECTED_OPENCLAW_VERSION="2026.7.1-2"

mkdir -p "$STATE_DIR"
exec > >(tee -a "$RUN_LOG") 2>&1

die() {
  printf '\nERROR: %s\n' "$*" >&2
  printf 'Working state preserved in: %s\n' "$STATE_DIR" >&2
  printf 'Repository left on branch: %s\n' "$(git -C "$REPO" branch --show-current 2>/dev/null || true)" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

for cmd in git sudo nix-instantiate nix-build nix-prefetch-url jq codex systemctl grep awk sed; do
  need "$cmd"
done

[[ -d "$REPO/.git" ]] || die "repository not found: $REPO"
cd "$REPO"

printf '=== HELIX MAJOR PASS ===\n'
printf 'Repository: %s\n' "$REPO"
printf 'State/logs: %s\n' "$STATE_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short
  die "working tree is not clean"
fi

sudo -v

git fetch origin main
git switch main
git pull --ff-only origin main

BASE_COMMIT="$(git rev-parse HEAD)"
BASE_SYSTEM="$(readlink -f /nix/var/nix/profiles/system)"
BASE_RUN_SYSTEM="$(readlink -f /run/current-system)"
BASE_KERNEL="$(uname -r)"
BASE_NVIDIA="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)"
BASE_OPENCLAW="$(openclaw --version 2>/dev/null || true)"

printf '\n=== BASELINE ===\n'
printf 'Git:        %s\n' "$BASE_COMMIT"
printf 'Profile:    %s\n' "$BASE_SYSTEM"
printf 'Running:    %s\n' "$BASE_RUN_SYSTEM"
printf 'Kernel:     %s\n' "$BASE_KERNEL"
printf 'NVIDIA:     %s\n' "${BASE_NVIDIA:-unknown}"
printf 'OpenClaw:   %s\n' "${BASE_OPENCLAW:-unknown}"

sudo nix-env -p /nix/var/nix/profiles/system --list-generations \
  | tee "$STATE_DIR/generations-before.txt"

printf '\n=== CURRENT 30-DAY GC DRY RUN ===\n'
sudo nix-collect-garbage --delete-older-than 14d --dry-run \
  |& tee "$STATE_DIR/gc-14d-dry-run.txt"

# Use the repository's deterministic Nixpkgs selection for all evaluation below.
# shellcheck source=/dev/null
source "$REPO/scripts/release-environment.sh"

printf '\n=== PACKAGE PREFLIGHT ===\n'
MISSING_JSON="$(
  nix-instantiate --eval --strict --json --expr '
    let
      p = import <nixpkgs> { config.allowUnfree = true; };
      names = [
        "nix-output-monitor"
        "nvd"
        "protonplus"
        "protontricks"
        "goverlay"
        "gamescope"
      ];
    in builtins.filter (name: !(builtins.hasAttr name p)) names
  '
)"
if [[ "$(jq 'length' <<<"$MISSING_JSON")" -ne 0 ]]; then
  printf 'Missing package attributes in selected Nixpkgs:\n'
  jq -r '.[]' <<<"$MISSING_JSON"
  die "package preflight failed"
fi
printf 'Required package attributes exist in selected Nixpkgs.\n'

printf '\n=== PREFETCH FIRST-PARTY OPENCLAW PACKAGING ===\n'
PREFETCH_OUTPUT="$(nix-prefetch-url --unpack --print-path "$NIX_OPENCLAW_URL")"
printf '%s\n' "$PREFETCH_OUTPUT" | tee "$STATE_DIR/nix-openclaw-prefetch.txt"

NIX_OPENCLAW_PATH="$(
  printf '%s\n' "$PREFETCH_OUTPUT" | grep '^/nix/store/' | tail -n1
)"
NIX_OPENCLAW_SHA256="$(
  printf '%s\n' "$PREFETCH_OUTPUT" | grep -v '^/nix/store/' | tail -n1
)"

[[ -n "$NIX_OPENCLAW_PATH" && -d "$NIX_OPENCLAW_PATH/nix/packages" ]] \
  || die "could not resolve prefetched nix-openclaw source path"
[[ -n "$NIX_OPENCLAW_SHA256" ]] \
  || die "could not resolve nix-openclaw source hash"

grep -q "releaseVersion = \"${EXPECTED_OPENCLAW_VERSION}\"" \
  "$NIX_OPENCLAW_PATH/nix/sources/openclaw-source.nix" \
  || die "pinned nix-openclaw revision does not contain expected OpenClaw ${EXPECTED_OPENCLAW_VERSION}"

printf 'nix-openclaw rev:    %s\n' "$NIX_OPENCLAW_REV"
printf 'nix-openclaw hash:   %s\n' "$NIX_OPENCLAW_SHA256"
printf 'OpenClaw expected:   %s\n' "$EXPECTED_OPENCLAW_VERSION"

git switch -c "$BRANCH"

cat > "$PROMPT_FILE" <<'PROMPT'
Work directly in /home/tristan/Projects/nixos-helix.

This is one coherent Helix workstation modernisation pass. Implement the entire request; do not merely describe it. Do not ask questions. Do not commit, push, run garbage collection, reboot, or run `nixos-rebuild switch`; the outer orchestration script owns final validation, activation, commit, and GC.

NON-NEGOTIABLE SAFETY / ARCHITECTURE
- This remains a NixOS 26.05, channel-based configuration. DO NOT convert the repository to flakes or Home Manager.
- Keep `system.stateVersion` unchanged.
- Keep the kernel policy on the NixOS 26.05 default 6.18 LTS family. DO NOT set `linuxPackages_latest`, a 7.x kernel, or another kernel override.
- Preserve the working NVIDIA configuration and current 595 driver selection from Nixpkgs.
- Do not edit hardware-configuration.nix.
- Do not enable unattended NixOS/kernel/channel upgrades.
- Preserve existing NAS/storage safety, monitoring, emulation, hamSteam, OpenSSH, controller, Plasma/Hyprland and local-LLM behaviour unless a change below explicitly requires integration.
- Preserve the current OpenClaw sandbox boundaries, localhost-only networking, Ollama provider/config, secret handling, and `OPENCLAW_NIX_MODE = "1"`.
- No mutable runtime package installers, no curl-pipe-shell installers, no npm global install, no broad chmod/chown, no deletion of user data.
- Follow existing repository style, module structure and tests. Update tests/invariants/documentation when behaviour changes.
- `./scripts/check.sh` must remain a meaningful full gate.

1. GC POLICY
Change the existing weekly Nix GC retention from 30d to 14d. Keep it weekly, persistent, with the existing randomized delay and automatic store optimisation. Do not invent a custom generation parser or a count-based pruning daemon.

2. SECURE, PINNED OPENCLAW
The selected NixOS 26.05 channel currently exposes insecure OpenClaw 2026.5.7. Replace that package source with the first-party `openclaw/nix-openclaw` packaging pinned immutably at:

  revision: __NIX_OPENCLAW_REV__
  source sha256 from `nix-prefetch-url --unpack`: __NIX_OPENCLAW_SHA256__

That fixed packaging revision's `nix/sources/openclaw-source.nix` pins OpenClaw 2026.7.1-2.

Requirements:
- Use a normal Nix source pin such as `pkgs.fetchFromGitHub` with the exact revision and fixed hash above. Do not use mutable `main`, a tag without a hash, `builtins.getFlake`, or convert this repo to flakes.
- Reuse the first-party package definitions under that fetched source (`nix/packages`) rather than rebuilding an ad-hoc npm package.
- Integrate it in a non-recursive way, preferably as a small repository-owned package/overlay module, so existing references to `pkgs.openclaw` remain clean.
- Expected resulting OpenClaw version is exactly 2026.7.1-2.
- Remove the old `nixpkgs.config.permittedInsecurePackages = [ "openclaw-2026.5.7" ];` exception once the new package is selected.
- Preserve `OPENCLAW_NIX_MODE = "1"` and the current OpenClaw service configuration/sandbox.
- Add an assertion or test that prevents accidental regression to OpenClaw < 2026.6.9 / the old 2026.5.7 package.
- Do not select beta OpenClaw.

3. MEMORY PRESSURE
Add a small dedicated system module for:
- zramSwap.enable = true
- zramSwap.algorithm = "zstd"
- zramSwap.memoryPercent = 50
- zramSwap.priority = 100
- systemd.oomd.enable = true
- systemd.oomd.enableRootSlice = true
- systemd.oomd.enableUserSlices = true
- systemd.oomd.enableSystemSlice = false

Helix has 32 GiB RAM and no disk swap. Do not create a disk swapfile/partition.

4. NIX UX
Add `nix-output-monitor` and `nvd` declaratively.
Improve the existing `scripts/rebuild.sh` so builds are pleasant when `nom` is available, but it MUST gracefully fall back to the existing raw output when `nom` is not yet installed (bootstrap/reinstall case). Preserve exit status with pipefail. Do not replace the repo's channel/release-selection architecture with `nh`.

5. GAMING TOOLBOX
Keep existing Steam, GameMode and MangoHud.
Add:
- ProtonPlus
- protontricks
- GOverlay
Enable GameScope through the native NixOS `programs.gamescope` module; do not duplicate-install the raw package. Leave capSysNice false unless the existing configuration demonstrably requires it.

Do not add per-game hacks or Borderlands-specific configuration.

6. HELIX HEALTH + UPDATE COMMANDS
Add repository-owned declarative commands installed system-wide:

`helix-health`
- concise, human-readable one-screen report
- NixOS version
- kernel
- current system generation/profile
- NVIDIA driver/GPU status
- memory plus zram/swap
- root/local-storage usage
- failed system units count/list
- failed user units count/list where available
- OpenClaw version + gateway status
- monitoring stack status
- age/identity of selected root NixOS channel when determinable
- health warnings should be visible but ordinary warnings should not make the command useless

`helix-update`
- operates on /home/tristan/Projects/nixos-helix
- refuses a dirty working tree
- explicitly runs `sudo nix-channel --update`
- runs repository validation
- builds the candidate
- shows an `nvd diff` against /run/current-system
- test-activates before switch
- switches only after successful validation/test
- prints the resulting generation and a clear rollback command
- no automatic GC as part of this command
- no unattended/background scheduling
- use `nom` when available with a safe fallback

7. HELIX THEME FAMILY
Refactor the existing "Helix Graphite + Fern" appearance into a palette-driven family while preserving Fern as the exact default appearance and preserving the same fonts, geometry, Breeze widget/decorations, border sizing, shadows and overall aesthetic.

Themes:
- fern      — current palette, unchanged
- petrol    — muted deep petrol/teal
- plum      — dusty aubergine/plum, not neon
- oxide     — muted rust/copper
- amber     — desaturated ochre/gold
- rosewood  — dark wine/rosewood, not gamer red
- hotdog    — faithful Hot Dog Stand colour violence: saturated yellow + red + black/white, while keeping Helix geometry/layout unchanged

For the tasteful siblings, keep the graphite chassis and text hierarchy essentially identical; only tint surfaces subtly and change the accent family. Avoid neon/cyberpunk styling.

Implement:
- `helix-theme list`
- `helix-theme current`
- `helix-theme fern|petrol|plum|oxide|amber|rosewood|hotdog`
- persist the selected theme in Tristan's user config/state; default/fallback is fern
- graphical-session login applies the persisted theme
- switching does not require root
- Fern remains compatible with the existing `helix-apply-theme` workflow; it can become a compatibility wrapper if appropriate
- apply the palette coherently to the surfaces the current theme already owns: Plasma colour scheme + wallpaper, Konsole, Ghostty appearance, Waybar, Mako, Fuzzel, and Steam custom CSS. GTK should remain Breeze-Dark where that is the current design.
- do not kill Steam during a theme switch; if Steam must be restarted for CSS to take effect, say so.
- SDDM may remain the default Fern system theme; do not make SDDM depend on mutable per-user state.
- `helix-theme list` should describe Hot Dog Stand as "regrettably available."
- Prefer generated/template assets from semantic palette data over seven hand-maintained copies where practical.
- Update the current theme tests so Fern fidelity remains covered and every new palette/scheme/command is validated.

Suggested accent families if useful; tune for contrast rather than copying blindly:
- petrol:   accent #5FA8A3, bright #79C2BC, deep #386D69, selection #2D5754
- plum:     accent #A47AB8, bright #C096D0, deep #654A73, selection #50395B
- oxide:    accent #BE7A55, bright #D69772, deep #794C35, selection #603B2B
- amber:    accent #C3A35D, bright #D8BC7A, deep #786537, selection #5D4E2C
- rosewood: accent #B66E7D, bright #CF8997, deep #734550, selection #59363E

Hotdog is intentionally exempt from restraint.

8. TESTS / DOCUMENTATION / QUALITY
- Update tests/system invariants and theme tests for new behaviour.
- Keep formatting and shellcheck clean.
- Do not weaken existing safety checks to make the build pass.
- Add concise documentation for `helix-health`, `helix-update`, `helix-theme`, GC retention, zram/OOM and the OpenClaw pin.
- Run focused local tests that do not require sudo where useful, but leave the full final gate to the outer script.
- At the end, print a concise summary of changed files, design decisions, and anything the outer script should pay attention to.
PROMPT

sed -i \
  -e "s|__NIX_OPENCLAW_REV__|${NIX_OPENCLAW_REV}|g" \
  -e "s|__NIX_OPENCLAW_SHA256__|${NIX_OPENCLAW_SHA256}|g" \
  "$PROMPT_FILE"

printf '\n=== CODEX IMPLEMENTATION PASS ===\n'
printf 'Prompt: %s\n' "$PROMPT_FILE"
codex exec "$(cat "$PROMPT_FILE")" \
  |& tee "$STATE_DIR/codex.log"

if [[ -z "$(git status --porcelain)" && "$(git rev-parse HEAD)" == "$BASE_COMMIT" ]]; then
  die "Codex returned without making repository changes"
fi

printf '\n=== CHANGESET ===\n'
git status --short
git diff --stat "$BASE_COMMIT"
git diff --check

printf '\n=== FULL REPOSITORY GATE ===\n'
./scripts/dev-shell.sh --run './scripts/check.sh'

printf '\n=== BUILD CANDIDATE SYSTEM ===\n'
NEW_SYSTEM="$(
  nix-build --no-out-link '<nixpkgs/nixos>' -A system \
    -I "nixos-config=$REPO/configuration.nix"
)"
printf 'Candidate: %s\n' "$NEW_SYSTEM"

[[ -x "$NEW_SYSTEM/sw/bin/nvd" ]] || die "candidate does not contain nvd"
[[ -x "$NEW_SYSTEM/sw/bin/nom" ]] || die "candidate does not contain nom"

printf '\n=== NVD SYSTEM DIFF ===\n'
"$NEW_SYSTEM/sw/bin/nvd" diff /run/current-system "$NEW_SYSTEM" || true

printf '\n=== STATIC CANDIDATE ASSERTIONS ===\n'
NEW_KERNEL="$(readlink -f "$NEW_SYSTEM/kernel")"
printf 'Candidate kernel: %s\n' "$NEW_KERNEL"
KERNEL_STORE_NAME="$(basename "$(dirname "$NEW_KERNEL")")"
grep -Eq '(^|-)linux-6\.18\.' <<<"$KERNEL_STORE_NAME" \
  || die "candidate kernel is not in the 6.18 LTS family"

CANDIDATE_OPENCLAW="$("$NEW_SYSTEM/sw/bin/openclaw" --version 2>/dev/null || true)"
printf 'Candidate OpenClaw: %s\n' "$CANDIDATE_OPENCLAW"
grep -q "$EXPECTED_OPENCLAW_VERSION" <<<"$CANDIDATE_OPENCLAW" \
  || die "candidate OpenClaw is not ${EXPECTED_OPENCLAW_VERSION}"

for exe in \
  helix-health helix-update helix-theme \
  protonplus protontricks goverlay gamescope \
  nom nvd; do
  [[ -x "$NEW_SYSTEM/sw/bin/$exe" ]] || die "candidate missing executable: $exe"
done

"$NEW_SYSTEM/sw/bin/helix-theme" list \
  | tee "$STATE_DIR/theme-list.txt"
grep -q 'fern' "$STATE_DIR/theme-list.txt" || die "theme list missing fern"
grep -q 'petrol' "$STATE_DIR/theme-list.txt" || die "theme list missing petrol"
grep -q 'plum' "$STATE_DIR/theme-list.txt" || die "theme list missing plum"
grep -q 'oxide' "$STATE_DIR/theme-list.txt" || die "theme list missing oxide"
grep -q 'amber' "$STATE_DIR/theme-list.txt" || die "theme list missing amber"
grep -q 'rosewood' "$STATE_DIR/theme-list.txt" || die "theme list missing rosewood"
grep -q 'hotdog' "$STATE_DIR/theme-list.txt" || die "theme list missing hotdog"
grep -qi 'regrettably available' "$STATE_DIR/theme-list.txt" \
  || die "Hot Dog Stand has become insufficiently regrettable"

printf '\n=== TEST ACTIVATE ===\n'
./scripts/rebuild.sh test

printf '\n=== RUNTIME ASSERTIONS AFTER TEST ===\n'
systemctl is-active --quiet systemd-oomd.service \
  || die "systemd-oomd is not active"

if ! swapon --show=NAME --noheadings 2>/dev/null | grep -q 'zram'; then
  zramctl || true
  swapon --show || true
  die "zram swap is not active"
fi
zramctl
swapon --show

systemctl --user is-active --quiet openclaw-gateway.service \
  || {
    systemctl --user status openclaw-gateway.service --no-pager -l || true
    journalctl --user -u openclaw-gateway.service -b -n 100 --no-pager || true
    die "OpenClaw gateway is not active"
  }

/run/current-system/sw/bin/openclaw --version \
  | tee "$STATE_DIR/openclaw-runtime-version.txt"
grep -q "$EXPECTED_OPENCLAW_VERSION" "$STATE_DIR/openclaw-runtime-version.txt" \
  || die "runtime OpenClaw is not ${EXPECTED_OPENCLAW_VERSION}"

nvidia-smi >/dev/null \
  || die "NVIDIA driver failed after test activation"

printf '\n=== HELIX HEALTH ===\n'
/run/current-system/sw/bin/helix-health \
  | tee "$STATE_DIR/health-after-test.txt"

printf '\n=== SWITCH ===\n'
./scripts/rebuild.sh switch

printf '\n=== COMMIT VALIDATED CHANGE ===\n'
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git diff --cached --check
  git commit -m "Modernize Helix workstation configuration"
fi

FINAL_COMMIT="$(git rev-parse HEAD)"

printf '\n=== APPLY DECLARED 14-DAY GC POLICY NOW ===\n'
sudo nix-collect-garbage --delete-older-than 14d \
  |& tee "$STATE_DIR/gc-14d.txt"

sudo nix-env -p /nix/var/nix/profiles/system --list-generations \
  | tee "$STATE_DIR/generations-after.txt"

GEN_BEFORE="$(
  grep -Ec '^[[:space:]]*[0-9]+' "$STATE_DIR/generations-before.txt" || true
)"
GEN_AFTER="$(
  grep -Ec '^[[:space:]]*[0-9]+' "$STATE_DIR/generations-after.txt" || true
)"

FINAL_SYSTEM="$(readlink -f /nix/var/nix/profiles/system)"
FINAL_OPENCLAW="$(/run/current-system/sw/bin/openclaw --version 2>/dev/null || true)"
FINAL_NVIDIA="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)"

cat > "$SUMMARY_FILE" <<EOF
Helix major pass completed successfully.

Branch:       $BRANCH
Base commit:  $BASE_COMMIT
Final commit: $FINAL_COMMIT
System:       $FINAL_SYSTEM
Kernel:       $(uname -r)
NVIDIA:       ${FINAL_NVIDIA:-unknown}
OpenClaw:     ${FINAL_OPENCLAW:-unknown}
Generations:  $GEN_BEFORE -> $GEN_AFTER
State/logs:   $STATE_DIR

Validated:
- 14-day weekly GC policy
- pinned first-party OpenClaw ${EXPECTED_OPENCLAW_VERSION}
- zram + systemd-oomd
- nom + nvd Nix UX
- ProtonPlus + protontricks + GameScope + GOverlay
- helix-health
- helix-update
- theme family: fern, petrol, plum, oxide, amber, rosewood, hotdog
- kernel remains on 6.18 LTS family
- NVIDIA still operational

Rollback:
  sudo nixos-rebuild --rollback switch

The validated commit is local on:
  $BRANCH

To publish the reviewed branch:
  git push -u origin $BRANCH

To merge it into main after living with it:
  git switch main
  git merge --ff-only $BRANCH
  git push origin main
EOF

printf '\n=== COMPLETE ===\n'
cat "$SUMMARY_FILE"

if command -v wl-copy >/dev/null 2>&1; then
  wl-copy < "$SUMMARY_FILE"
  printf '\nSummary copied to the Wayland clipboard.\n'
elif command -v pbcopy >/dev/null 2>&1; then
  pbcopy < "$SUMMARY_FILE"
  printf '\nSummary copied to the clipboard.\n'
fi
