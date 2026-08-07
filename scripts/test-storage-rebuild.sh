#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/storage-rebuild-lib.sh
source "$repo_root/scripts/storage-rebuild-lib.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HELIX_STORAGE_TEST_MODE=1 HELIX_STORAGE_TEST_BACKUP_OK=1
export HELIX_STORAGE_TEST_DEVICE_DB=$tmp/devices.tsv

fail() { printf 'TEST FAIL: %s\n' "$*" >&2; exit 1; }
rejects() { ( "$@" ) >/dev/null 2>&1 && fail "unexpected success: $*" || true; }

disk_bytes=512110190592
IFS=$'\t' read -r ef es rf rs lu rb reserve <<<"$(storage_calculate_os_layout "$disk_bytes" 512)"
[[ $((es - ef + 1)) -eq $((10 * HELIX_GIB / 512)) ]] || fail 'ESP is not 10 GiB'
[[ $reserve -eq $((240 * HELIX_GIB / 512)) && $((lu - rs)) -eq $reserve ]] || fail 'reserve is not 240 GiB'
[[ $rf -eq $((es + 1)) && $rb -ge $((200 * HELIX_GIB)) ]] || fail 'root calculation is wrong'
rejects storage_calculate_os_layout $((440 * HELIX_GIB)) 512
[[ $(storage_partition_path /dev/nvme9n1 2) == /dev/nvme9n1p2 ]]
[[ $(storage_partition_path /dev/sdz 1) == /dev/sdz1 ]]

cat >"$HELIX_STORAGE_TEST_DEVICE_DB" <<'EOF'
/dev/disk/by-id/os	/dev/nvme9n1	disk	512110190592	0	0	OS Model	OS123	-	-	no	no
/dev/disk/by-id/a	/dev/sda	disk	1000204886016	0	0	SSD A	A123	-	-	no	no
/dev/disk/by-id/b	/dev/sdb	disk	1000204886016	0	0	SSD B	B123	-	-	no	no
/dev/disk/by-id/part	/dev/sdc1	part	1000	0	0	Part	P1	-	-	no	no
/dev/disk/by-id/games	/dev/sdc	disk	1000	0	0	Games	G1	d07ac88e-34f6-4d56-9941-5ceaf52fd6bb	-	no	no
/dev/disk/by-id/mounted	/dev/sdd	disk	1000	0	0	Mounted	M1	-	/mnt/x	no	no
/dev/disk/by-id/removable	/dev/sde	disk	1000	0	1	Remove	R1	-	-	no	no
/dev/disk/by-id/rotational	/dev/sdf	disk	512110190592	1	0	Rotate	T1	-	-	no	no
EOF
cat >"$tmp/manifest" <<EOF
BACKUP_SET=helix-reinstall-20260807-120000
APPROVED_COMMIT=0123456789012345678901234567890123456789
EFI_SIZE_GIB=10
WINDOWS_RESERVE_GIB=240
OS_DISK_BY_ID=/dev/disk/by-id/os
OS_EXPECTED_MODEL=OS Model
OS_EXPECTED_SERIAL=OS123
OS_MIN_BYTES=500000000000
OS_MAX_BYTES=520000000000
OS_ROLE=helix-os
SSD_A_BY_ID=/dev/disk/by-id/a
SSD_A_EXPECTED_MODEL=SSD A
SSD_A_EXPECTED_SERIAL=A123
SSD_A_MIN_BYTES=990000000000
SSD_A_MAX_BYTES=1010000000000
SSD_A_ROLE=helix-ssd-a
SSD_B_BY_ID=/dev/disk/by-id/b
SSD_B_EXPECTED_MODEL=SSD B
SSD_B_EXPECTED_SERIAL=B123
SSD_B_MIN_BYTES=990000000000
SSD_B_MAX_BYTES=1010000000000
SSD_B_ROLE=helix-ssd-b
EOF
storage_load_manifest "$tmp/manifest"
storage_validate_three_distinct_resolved
storage_validate_target OS true
storage_validate_backup

test_reject() {
  local byid=$1 model=$2 serial=$3 min=${4:-0} max=${5:-9999999999999} nonrot=${6:-false}
  STORAGE_MANIFEST[SSD_A_BY_ID]=$byid; STORAGE_MANIFEST[SSD_A_EXPECTED_MODEL]=$model
  STORAGE_MANIFEST[SSD_A_EXPECTED_SERIAL]=$serial; STORAGE_MANIFEST[SSD_A_MIN_BYTES]=$min
  STORAGE_MANIFEST[SSD_A_MAX_BYTES]=$max
  rejects storage_validate_target SSD_A "$nonrot"
}
test_reject /dev/disk/by-id/part Part P1
test_reject /dev/disk/by-id/games Games G1
test_reject /dev/disk/by-id/mounted Mounted M1
test_reject /dev/disk/by-id/removable Remove R1
test_reject /dev/disk/by-id/rotational Rotate T1 500000000000 520000000000 true
test_reject /dev/disk/by-id/a Wrong A123
test_reject /dev/disk/by-id/a 'SSD A' Wrong
test_reject /dev/disk/by-id/a 'SSD A' A123 1 10
HELIX_STORAGE_TEST_BACKUP_OK=0 rejects storage_validate_backup

STORAGE_MANIFEST[OS_DISK_BY_ID]=/dev/disk/by-id/a
rejects storage_validate_three_distinct_resolved
grep -q -- '--run requires an interactive terminal' "$repo_root/scripts/prepare-os-drive.sh" || fail 'missing TTY gate'
grep -q 'PLAN ONLY: no block device was changed' "$repo_root/scripts/prepare-os-drive.sh" || fail 'plan is unclear'
grep -q 'HELIX_GAMES_UUID' "$repo_root/scripts/storage-rebuild-lib.sh" || fail 'games guard absent'
! grep -Eq '(mkfs|wipefs|sgdisk)[^\n]*\*' "$repo_root/scripts/prepare-os-drive.sh" "$repo_root/scripts/reclaim-linux-ssds.sh" || fail 'block wildcard found'
[[ $(grep -h 'label=HELIX_' "$repo_root/scripts/reclaim-linux-ssds.sh" | sort -u | wc -l) -eq 1 ]] || fail 'SSD label derivation changed'
! grep -Eq 'mkfs.*WINDOWS|NTFS|ntfs' "$repo_root/scripts/prepare-os-drive.sh" || fail 'Windows reserve is formatted'
printf 'Storage rebuild synthetic safety tests passed; no real device or NAS was contacted.\n'
