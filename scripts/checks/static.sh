#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

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
mapfile -t shell_files < <(find scripts -type f -name '*.sh' -print | sort)
bash -n "${shell_files[@]}"
mapfile -t top_level_shell_files < <(find scripts -maxdepth 1 -type f -name '*.sh' -print | sort)

if grep -Eq '\b(mkfs|parted|fdisk|sgdisk|wipefs|mount|umount|swapon|swapoff|mkswap|e2label|fatlabel)\b' \
  scripts/backup-for-reinstall.sh scripts/reinstall-preflight.sh \
  scripts/reinstall-postflight.sh scripts/restore-after-reinstall.sh \
  scripts/check-install-storage.sh; then
  printf 'A destructive storage command entered a read-only reinstall helper.\n' >&2
  exit 1
fi

printf 'Running ShellCheck...\n'
shellcheck -x "${top_level_shell_files[@]}"

printf 'Checking Nix dead code and lint...\n'
deadnix --fail --exclude hardware-configuration.nix -- .
statix check . -i hardware-configuration.nix

printf 'Checking repository-local module boundaries...\n'
if grep -Rqs '../../hamCade' profiles; then
  printf 'A NixOS profile still imports the sibling private hamCade checkout.\n' >&2
  exit 1
fi
if grep -RqiE 'arcade|mame' profiles/emulation.nix profiles/emulation; then
  printf 'Generic Helix emulation regained arcade/MAME ownership; arcade belongs to hamCade.\n' >&2
  exit 1
fi
grep -qF '1d5a2bbc315e617b3062641cbbde1f549f78d065' vendor/hamcade/dependencies.nix

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

printf 'Validating the Helix theme family and merge fixtures...\n'
python3 scripts/test-theme-settings.py
python3 scripts/test-fan-commission.py
python3 -m json.tool config/monitoring/helix-overview.json >/dev/null

./scripts/test-reinstall-safety.sh
./scripts/test-reinstall-restore.sh

