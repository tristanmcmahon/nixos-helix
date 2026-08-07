#!/usr/bin/env bash
set -euo pipefail

# Read-only evidence collection. This script never needs sudo and never writes a disk.
output=${1:-}
tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT

parent_disk() {
  local node=$1 parent
  node=${node%%\[*}
  [[ -b $node ]] || return 0
  while parent=$(lsblk -dnro PKNAME "$node") && [[ -n $parent ]]; do node=/dev/$parent; done
  printf '%s' "$node"
}

{
  printf 'HELIX STORAGE INVENTORY (READ ONLY)\n'
  printf 'hostname: %s\ndate: %s\nUEFI: %s\n' "$(hostname)" "$(date --iso-8601=seconds)" "$([[ -d /sys/firmware/efi ]] && printf yes || printf no)"
  for path in / /boot /mnt/games_nvme; do
    source=$(findmnt -nro SOURCE --target "$path" 2>/dev/null || true)
    printf '%s source: %s; disk: %s\n' "$path" "${source:-unmounted}" "$(parent_disk "$source")"
  done
  printf '\nBlock topology:\n'
  lsblk -e7 -o NAME,PATH,SIZE,TYPE,TRAN,ROTA,RM,MODEL,SERIAL,WWN,PTTYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS,PKNAME
  printf '\nStable whole-disk identities:\n'
  find /dev/disk/by-id -maxdepth 1 -type l ! -name '*-part[0-9]*' -printf '%p\t%l\n' 2>/dev/null | sort || true
  printf '\nHolders:\n'
  for sys_node in /sys/class/block/*; do
    name=${sys_node##*/}; holders=()
    for holder in "$sys_node"/holders/*; do [[ -e $holder ]] && holders+=("${holder##*/}"); done
    ((${#holders[@]})) && printf '%s\t%s\n' "$name" "${holders[*]}"
  done
  printf '\nProtected UUID %s:\n' 'd07ac88e-34f6-4d56-9941-5ceaf52fd6bb'
  lsblk -nrpo PATH,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINTS | awk '$5 == "d07ac88e-34f6-4d56-9941-5ceaf52fd6bb"'
  printf '\nBEGIN_STORAGE_TSV\nby_id\tkernel_path\ttransport\tbytes\trotational\tremovable\tmodel\tserial\twwn\tpttype\n'
  while IFS= read -r disk; do
    mapfile -t ids < <(find /dev/disk/by-id -maxdepth 1 -type l ! -name '*-part[0-9]*' -samefile "$disk" -print 2>/dev/null | sort)
    ((${#ids[@]})) || ids=('')
    for id in "${ids[@]}"; do
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$disk" \
        "$(lsblk -dnro TRAN "$disk" | xargs)" "$(lsblk -bdnro SIZE "$disk" | xargs)" \
        "$(lsblk -dnro ROTA "$disk" | xargs)" "$(lsblk -dnro RM "$disk" | xargs)" \
        "$(lsblk -dnro MODEL "$disk" | xargs)" "$(lsblk -dnro SERIAL "$disk" | xargs)" \
        "$(lsblk -dnro WWN "$disk" | xargs)" "$(lsblk -dnro PTTYPE "$disk" | xargs)"
    done
  done < <(lsblk -dnpo PATH,TYPE | awk '$2 == "disk" {print $1}')
  printf 'END_STORAGE_TSV\n'
  if command -v smartctl >/dev/null; then
    printf '\nSMART identity and health:\n'
    while IFS= read -r disk; do
      printf '\n[%s]\n' "$disk"
      smartctl -i -H "$disk" 2>&1 | sed -n '/Model\|Serial\|SMART overall-health\|SMART Health Status\|NVMe Version/p' || true
    done < <(lsblk -dnpo PATH,TYPE | awk '$2 == "disk" {print $1}')
  fi
} >"$tmp"

cat "$tmp"
if [[ -n $output ]]; then
  [[ ! -e $output ]] || { printf 'Refusing to overwrite %s\n' "$output" >&2; exit 1; }
  install -m 0600 "$tmp" "$output"
fi
