#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT

printf 'hardware\n' >"$temporary_directory/a"
cp "$temporary_directory/a" "$temporary_directory/b"
"$repo_root/scripts/verify-hardware-continuity.sh" \
  "$temporary_directory/a" "$temporary_directory/b" >/dev/null
printf 'different\n' >"$temporary_directory/b"
if "$repo_root/scripts/verify-hardware-continuity.sh" \
  "$temporary_directory/a" "$temporary_directory/b" >/dev/null 2>&1; then
  exit 1
fi

backup_script=$repo_root/scripts/backup-for-reinstall.sh
grep -qxF 'backup_root=/mnt/infernalnexus/nas1/backup' "$backup_script"
grep -qxF 'expected_source=//192.168.1.8/nas1' "$backup_script"
grep -qF "findmnt -rn --target \"\$nas_mount\" --types cifs" "$backup_script"
grep -qF "[[ \${#nas_records[@]} -eq 1 ]]" "$backup_script"
grep -qF "tar --create --file=\"\$incomplete_path/home-tristan.tar\"" "$backup_script"
grep -qF -- "--exclude='home/tristan/.local/share/Steam/steamapps/common'" "$backup_script"
grep -qF "mv --no-clobber -- \"\$incomplete_path\" \"\$final_path\"" "$backup_script"
if "$backup_script" unexpected-argument >/dev/null 2>&1; then
  printf 'Backup command accepted a destination argument.\n' >&2
  exit 1
fi

for required_file in COMPLETE SHA256SUMS BACKUP-README.txt \
  home-tristan.tar etc-nixos-secrets.tar; do
  grep -qF "$required_file" "$repo_root/scripts/reinstall-postflight.sh"
done
grep -qF '/mnt/infernalnexus/nas1/backup' "$repo_root/scripts/reinstall-preflight.sh"
grep -qF './scripts/backup-for-reinstall.sh' "$repo_root/docs/reinstall.md"

if grep -Eq '\b(mkfs|parted|fdisk|sgdisk|wipefs)\b' \
  "$repo_root/scripts/backup-for-reinstall.sh" \
  "$repo_root/scripts/reinstall-preflight.sh" \
  "$repo_root/scripts/reinstall-postflight.sh"; then
  printf 'A destructive storage command entered a reinstall helper.\n' >&2
  exit 1
fi

if grep -qF '/mnt/games_nvme' "$backup_script"; then
  printf 'The games NVMe was encoded as a backup source or destination.\n' >&2
  exit 1
fi

obsolete_pattern='HELIX_BACKUP_''PATH|VERIFIED-''BACKUP|backup-source-''lib|create-backup-''manifest'
if git -C "$repo_root" grep -nE "$obsolete_pattern" \
  -- . ':!docs/codex-canonical-nas-backup.md'; then
  printf 'An obsolete backup mechanism remains.\n' >&2
  exit 1
fi

if git -C "$repo_root" ls-files | grep -Ei \
  '(^|/)(COMPLETE|SHA256SUMS|.*\.(tar|tar\.(gz|xz|zst)|tgz|zip|7z))$'; then
  printf 'A backup marker, checksum manifest, or archive-shaped file is tracked.\n' >&2
  exit 1
fi

[[ ! -e "$repo_root/scripts/backup-source-"lib.sh ]]
[[ ! -e "$repo_root/scripts/create-backup-"manifest.sh ]]
printf 'Reinstall safety tests passed.\n'
