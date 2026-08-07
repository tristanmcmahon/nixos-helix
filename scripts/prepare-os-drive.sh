#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/storage-rebuild-lib.sh
source "$repo_root/scripts/storage-rebuild-lib.sh"

[[ $# -eq 2 && ($1 == --plan || $1 == --run) ]] || { printf 'Usage: %s --plan|--run MANIFEST\n' "$0" >&2; exit 2; }
mode=$1; manifest=$2
storage_load_manifest "$manifest"
storage_validate_repo
storage_validate_backup
storage_validate_three_distinct_resolved
storage_validate_target OS true
IFS=$'\t' read -r esp_first esp_last root_first root_last last_usable root_bytes reserve_sectors \
  <<<"$(storage_calculate_os_layout "$TARGET_SIZE" "$(blockdev --getss "$TARGET_DISK" 2>/dev/null || printf 512)")"
sector_bytes=$(blockdev --getss "$TARGET_DISK" 2>/dev/null || printf 512)

printf 'Verified OS target (nothing has been changed):\n'
storage_print_disk "$TARGET_DISK"
printf 'Identity: %s\nModel: %s\nSerial: %s\nBytes: %s\n' "$TARGET_BY_ID" "$TARGET_MODEL" "$TARGET_SERIAL" "$TARGET_SIZE"
printf 'Proposed sectors: ESP %s-%s (10 GiB); ROOT %s-%s (%s bytes); unallocated %s-%s (240 GiB).\n' \
  "$esp_first" "$esp_last" "$root_first" "$root_last" "$root_bytes" "$((root_last + 1))" "$last_usable"
[[ $mode == --run ]] || { printf 'PLAN ONLY: no block device was changed.\n'; exit 0; }

[[ ${HELIX_STORAGE_TEST_MODE:-0} != 1 ]] || storage_fail 'run mode is disabled under tests'
[[ $EUID -eq 0 ]] || storage_fail '--run requires root'
[[ -t 0 && -t 1 ]] || storage_fail '--run requires an interactive terminal'
storage_require_installer_environment
phrase="ERASE AND REBUILD HELIX OS DISK $TARGET_BY_ID SERIAL $TARGET_SERIAL BACKUP ${STORAGE_MANIFEST[BACKUP_SET]}"
printf 'Type exactly:\n%s\n> ' "$phrase"
IFS= read -r confirmation
[[ $confirmation == "$phrase" ]] || storage_fail 'confirmation did not match exactly'

# No globs are used: each currently enumerated child and then the whole disk is named explicitly.
mapfile -t old_nodes < <(lsblk -nrpo PATH "$TARGET_DISK" | tail -n +2)
for node in "${old_nodes[@]}"; do wipefs --all --force "$node"; done
wipefs --all --force "$TARGET_DISK"
sgdisk --zap-all "$TARGET_DISK"
sgdisk --clear --new="1:${esp_first}:${esp_last}" --typecode=1:ef00 --change-name=1:HELIX_EFI \
  --new="2:${root_first}:${root_last}" --typecode=2:8300 --change-name=2:HELIX_ROOT "$TARGET_DISK"
partprobe "$TARGET_DISK"; udevadm settle
actual_esp_first=$(sgdisk --info=1 "$TARGET_DISK" | awk '/First sector:/ {print $3}')
actual_esp_last=$(sgdisk --info=1 "$TARGET_DISK" | awk '/Last sector:/ {print $3}')
actual_root_first=$(sgdisk --info=2 "$TARGET_DISK" | awk '/First sector:/ {print $3}')
actual_root_last=$(sgdisk --info=2 "$TARGET_DISK" | awk '/Last sector:/ {print $3}')
[[ $actual_esp_first == "$esp_first" && $actual_esp_last == "$esp_last" && \
   $actual_root_first == "$root_first" && $actual_root_last == "$root_last" ]] || \
  storage_fail 'created GPT boundaries differ from the reviewed plan'
[[ $(sgdisk --print "$TARGET_DISK" | awk '$1 ~ /^[0-9]+$/ {count++} END {print count+0}') -eq 2 ]] || \
  storage_fail 'created OS GPT contains an unexpected partition count'
esp=$(storage_partition_path "$TARGET_DISK" 1); root=$(storage_partition_path "$TARGET_DISK" 2)
[[ -b $esp && -b $root ]] || storage_fail 'new partition nodes did not appear'
mkfs.fat -F 32 -n HELIX_EFI "$esp"
mkfs.ext4 -F -L HELIX_ROOT "$root"
[[ $(blkid -s LABEL -o value "$esp") == HELIX_EFI && $(blkid -s TYPE -o value "$esp") == vfat ]] || storage_fail 'ESP verification failed'
[[ $(blkid -s LABEL -o value "$root") == HELIX_ROOT && $(blkid -s TYPE -o value "$root") == ext4 ]] || storage_fail 'root verification failed'
[[ $(blockdev --getsize64 "$root") -ge $((200 * HELIX_GIB)) ]] || storage_fail 'formatted root is below 200 GiB'
install -d -m 0755 /mnt /mnt/boot
mount "$root" /mnt
mount -o umask=0077 "$esp" /mnt/boot
printf 'OS disk rebuilt and verified; trailing 240 GiB remains unallocated. NixOS was not installed.\n'
