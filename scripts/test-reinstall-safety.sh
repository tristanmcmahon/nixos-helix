#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT
# shellcheck source=/dev/null
source "$repo_root/scripts/backup-source-lib.sh"

printf 'hardware\n' >"$temporary_directory/a"
cp "$temporary_directory/a" "$temporary_directory/b"
"$repo_root/scripts/verify-hardware-continuity.sh" "$temporary_directory/a" "$temporary_directory/b" >/dev/null
printf 'different\n' >"$temporary_directory/b"
if "$repo_root/scripts/verify-hardware-continuity.sh" "$temporary_directory/a" "$temporary_directory/b" >/dev/null 2>&1; then exit 1; fi

backup=$temporary_directory/backup
mkdir "$backup"
printf 'data\n' >"$backup/file"
"$repo_root/scripts/create-backup-manifest.sh" "$backup" >/dev/null
if grep -q 'SHA256SUMS' "$backup/SHA256SUMS"; then exit 1; fi
(cd "$backup" && sha256sum --check SHA256SUMS >/dev/null)

[[ $(backup_source_classify ext4 nvme0n1 ext4 sda /dev/sda1) == separate-disk:sda ]]
if backup_source_classify ext4 nvme0n1 ext4 nvme0n1 /dev/nvme0n1p7 >/dev/null; then exit 1; fi
[[ $(backup_source_classify ext4 nvme0n1 nfs4 '' server:/backup) == network:nfs4:server:/backup ]]
if backup_source_classify ext4 nvme0n1 none '' /root/backup >/dev/null; then exit 1; fi
printf 'Reinstall safety tests passed.\n'
