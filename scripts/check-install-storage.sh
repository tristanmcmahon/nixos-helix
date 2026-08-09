#!/usr/bin/env bash
set -euo pipefail

# Read-only installer check. It never decides whether a disk is safe to erase.
games_uuid=d07ac88e-34f6-4d56-9941-5ceaf52fd6bb
[[ $# -eq 0 ]] || { printf 'Usage: %s\n' "${0##*/}" >&2; exit 2; }
if [[ $EUID -ne 0 ]]; then
  exec sudo -- "$0"
fi
[[ -d /sys/firmware/efi ]] || {
  printf 'FAIL: installer was not booted in UEFI mode.\n' >&2
  exit 1
}

os_serial=S463NF0M914938Z
ssd_a_serial=S2PWNX0HA06906Y
ssd_b_serial=S21HNXBG406937R
games_serial=S4EWNX0NA44184L

one_by_label() {
  local label=$1 expected_type=$2
  mapfile -t matches < <(blkid -t "LABEL=$label" -o device)
  [[ ${#matches[@]} -eq 1 ]] || {
    printf 'FAIL: expected exactly one %s filesystem; found %s.\n' "$label" "${#matches[@]}" >&2
    exit 1
  }
  [[ $(blkid -s TYPE -o value "${matches[0]}") == "$expected_type" ]] || {
    printf 'FAIL: %s is not %s.\n' "$label" "$expected_type" >&2
    exit 1
  }
  printf '%s' "${matches[0]}"
}

physical_disk() {
  local node=$1 parent
  node=$(readlink -f "$node")
  while parent=$(lsblk -dnro PKNAME "$node") && [[ -n $parent ]]; do node=/dev/$parent; done
  printf '%s' "$node"
}

verify_serial() {
  local disk=$1 expected=$2 role=$3 actual
  actual=$(lsblk -dnro SERIAL "$disk" | xargs)
  [[ $actual == "$expected" ]] || {
    printf 'FAIL: %s parent serial is %s; expected %s.\n' "$role" "$actual" "$expected" >&2
    exit 1
  }
}

printf 'Helix installation storage check (read only)\nUEFI boot: yes\n\n'
lsblk -e7 -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL,SERIAL

root=$(one_by_label HELIX_ROOT ext4)
efi=$(one_by_label HELIX_EFI vfat)
ssd_a=$(one_by_label HELIX_SSD_A ext4)
ssd_b=$(one_by_label HELIX_SSD_B ext4)
mapfile -t games_matches < <(blkid -t "UUID=$games_uuid" -o device)
[[ ${#games_matches[@]} -eq 1 ]] || {
  printf 'FAIL: expected protected GAMES_NVME UUID exactly once; found %s.\n' \
    "${#games_matches[@]}" >&2; exit 1;
}
games=${games_matches[0]}
[[ $(blkid -s TYPE -o value "$games") == ext4 ]] || {
  printf 'FAIL: protected GAMES_NVME is not ext4.\n' >&2; exit 1;
}
[[ $(blkid -s LABEL -o value "$games") == GAMES_NVME ]] || {
  printf 'FAIL: protected games filesystem label is not GAMES_NVME.\n' >&2; exit 1;
}

root_disk=$(physical_disk "$root"); efi_disk=$(physical_disk "$efi")
[[ $root_disk == "$efi_disk" ]] || { printf 'FAIL: HELIX_ROOT and HELIX_EFI are on different disks.\n' >&2; exit 1; }
ssd_a_disk=$(physical_disk "$ssd_a")
ssd_b_disk=$(physical_disk "$ssd_b")
games_disk=$(physical_disk "$games")
verify_serial "$root_disk" "$os_serial" HELIX_ROOT
verify_serial "$efi_disk" "$os_serial" HELIX_EFI
verify_serial "$ssd_a_disk" "$ssd_a_serial" HELIX_SSD_A
verify_serial "$ssd_b_disk" "$ssd_b_serial" HELIX_SSD_B
verify_serial "$games_disk" "$games_serial" GAMES_NVME
efi_bytes=$(lsblk -bdno SIZE "$efi" | xargs)
((efi_bytes >= 9 * 1024 * 1024 * 1024 && efi_bytes <= 11 * 1024 * 1024 * 1024)) || {
  printf 'FAIL: HELIX_EFI size is not approximately 10 GiB: %s bytes.\n' "$efi_bytes" >&2; exit 1;
}

printf '\nVerified filesystems:\n'
printf 'HELIX_ROOT: %s\nHELIX_EFI: %s (%s bytes)\nHELIX_SSD_A: %s\nHELIX_SSD_B: %s\n' \
  "$root" "$efi" "$efi_bytes" "$ssd_a" "$ssd_b"
printf 'GAMES_NVME protected UUID: %s (%s)\n' "$games_uuid" "$games"
printf '\nOS disk and free-space evidence (manually confirm about 240 GiB unallocated):\n'
lsblk -b -o NAME,PATH,START,SIZE,TYPE,FSTYPE,LABEL,PARTUUID "$root_disk"
disk_bytes=$(lsblk -bdno SIZE "$root_disk" | xargs)
partition_bytes=$(lsblk -bnro SIZE,TYPE "$root_disk" | awk '$2 == "part" {total += $1} END {print total + 0}')
unallocated_bytes=$((disk_bytes - partition_bytes))
unallocated_gib=$(awk -v bytes="$unallocated_bytes" 'BEGIN {printf "%.2f", bytes / 1073741824}')
printf 'Disk bytes: %s; partition bytes: %s\n' "$disk_bytes" "$partition_bytes"
printf 'Estimated unallocated: %s bytes (%s GiB)\n' "$unallocated_bytes" "$unallocated_gib"

printf '\nMounts below /mnt outside the installer root and EFI:\n'
unexpected=false
while IFS= read -r target; do
  [[ $target == /mnt || $target == /mnt/boot ]] && continue
  printf '%s\n' "$target"; unexpected=true
done < <(findmnt -rn -o TARGET --submounts /mnt 2>/dev/null || true)
if [[ $unexpected == true ]]; then
  printf 'FAIL: unexpected filesystem is mounted beneath /mnt.\n' >&2
  exit 1
fi
printf 'none\n'
printf 'This evidence is not permission to erase or modify any disk.\n'
