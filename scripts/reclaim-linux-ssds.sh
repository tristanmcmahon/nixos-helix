#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/storage-rebuild-lib.sh
source "$repo_root/scripts/storage-rebuild-lib.sh"
[[ $# -eq 2 && ($1 == --plan || $1 == --run) ]] || { printf 'Usage: %s --plan|--run MANIFEST\n' "$0" >&2; exit 2; }
mode=$1
storage_load_manifest "$2"
storage_validate_repo; storage_validate_backup; storage_validate_three_distinct_resolved

for role in SSD_A SSD_B; do
  storage_validate_target "$role" true
  printf '\nVerified %s target (nothing has been changed):\n' "$role"
  storage_print_disk "$TARGET_DISK"
  printf 'Identity: %s\nModel: %s\nSerial: %s\nBytes: %s\nPlan: GPT, one ext4 partition, label HELIX_%s.\n' \
    "$TARGET_BY_ID" "$TARGET_MODEL" "$TARGET_SERIAL" "$TARGET_SIZE" "$role"
done
[[ $mode == --run ]] || { printf 'PLAN ONLY: no block device was changed.\n'; exit 0; }
[[ ${HELIX_STORAGE_TEST_MODE:-0} != 1 ]] || storage_fail 'run mode is disabled under tests'
[[ $EUID -eq 0 ]] || storage_fail '--run requires root'
[[ -t 0 && -t 1 ]] || storage_fail '--run requires an interactive terminal'
storage_require_installer_environment

completed=()
for role in SSD_A SSD_B; do
  storage_validate_target "$role" true
  label=HELIX_$role
  phrase="ERASE HELIX $role $TARGET_BY_ID SERIAL $TARGET_SERIAL"
  printf '\nType exactly to erase %s:\n%s\n> ' "$role" "$phrase"
  IFS= read -r confirmation
  [[ $confirmation == "$phrase" ]] || { printf 'Stopped. Completed targets: %s\n' "${completed[*]:-none}" >&2; exit 1; }
  mapfile -t old_nodes < <(lsblk -nrpo PATH "$TARGET_DISK" | tail -n +2)
  for node in "${old_nodes[@]}"; do wipefs --all --force "$node"; done
  wipefs --all --force "$TARGET_DISK"
  sgdisk --zap-all "$TARGET_DISK"
  sgdisk --clear --new=1:0:0 --typecode=1:8300 --change-name="1:$label" "$TARGET_DISK"
  partprobe "$TARGET_DISK"; udevadm settle
  partition=$(storage_partition_path "$TARGET_DISK" 1)
  [[ -b $partition ]] || storage_fail "$role partition node did not appear; completed: ${completed[*]:-none}"
  mkfs.ext4 -F -L "$label" "$partition"
  [[ $(blkid -s TYPE -o value "$partition") == ext4 && $(blkid -s LABEL -o value "$partition") == "$label" ]] || \
    storage_fail "$role filesystem verification failed; completed: ${completed[*]:-none}"
  [[ $(lsblk -nrpo TYPE "$TARGET_DISK" | grep -c '^part$') -eq 1 ]] || storage_fail "$role has extra partitions"
  completed+=("$role:$partition")
  printf '%s completed and verified. Partial state: %s\n' "$role" "${completed[*]}"
done
printf 'Both SSD operations completed independently: %s\n' "${completed[*]}"
