#!/usr/bin/env bash

# Shared fail-closed validation for the two dedicated destructive storage tools.
# Callers must enable strict mode before sourcing this file.

HELIX_CANONICAL_REPO=/home/tristan/Projects/nixos-helix
HELIX_BACKUP_ROOT=/mnt/infernalnexus/nas1/backup
HELIX_NAS_MOUNT=/mnt/infernalnexus/nas1
HELIX_NAS_SOURCE=//192.168.1.8/nas1
HELIX_GAMES_UUID=d07ac88e-34f6-4d56-9941-5ceaf52fd6bb
HELIX_GIB=$((1024 * 1024 * 1024))

storage_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  # Exit, rather than merely returning, so validation cannot accidentally
  # continue when a caller evaluates a function in a conditional context.
  exit 1
}

storage_partition_path() {
  local disk=$1 number=$2
  if [[ $disk =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$disk" "$number"
  else
    printf '%s%s\n' "$disk" "$number"
  fi
}

storage_calculate_os_layout() {
  local disk_bytes=$1 sector_bytes=$2
  [[ $disk_bytes =~ ^[0-9]+$ && $sector_bytes =~ ^[0-9]+$ && $sector_bytes -gt 0 ]] || \
    storage_fail 'invalid disk or sector size'
  ((disk_bytes % sector_bytes == 0)) || storage_fail 'disk size is not sector aligned'
  local total_sectors=$((disk_bytes / sector_bytes))
  local table_sectors=$(((16384 + sector_bytes - 1) / sector_bytes))
  local first_aligned=$(((1024 * 1024 + sector_bytes - 1) / sector_bytes))
  local esp_sectors=$((10 * HELIX_GIB / sector_bytes))
  local reserve_sectors=$((240 * HELIX_GIB / sector_bytes))
  local last_usable=$((total_sectors - table_sectors - 2))
  local esp_first=$first_aligned
  local esp_last=$((esp_first + esp_sectors - 1))
  local root_first=$((esp_last + 1))
  local root_last=$((last_usable - reserve_sectors))
  local root_bytes=$(((root_last - root_first + 1) * sector_bytes))
  ((root_last >= root_first && root_bytes >= 200 * HELIX_GIB)) || \
    storage_fail 'OS target would provide less than 200 GiB for HELIX_ROOT'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$esp_first" "$esp_last" "$root_first" "$root_last" "$last_usable" \
    "$root_bytes" "$reserve_sectors"
}

storage_load_manifest() {
  local manifest=$1 line key value
  [[ -f $manifest && ! -L $manifest ]] || storage_fail 'manifest must be a regular non-symlink file'
  declare -gA STORAGE_MANIFEST=()
  local allowed='^(BACKUP_SET|APPROVED_COMMIT|EFI_SIZE_GIB|WINDOWS_RESERVE_GIB|OS_DISK_BY_ID|OS_EXPECTED_MODEL|OS_EXPECTED_SERIAL|OS_MIN_BYTES|OS_MAX_BYTES|OS_ROLE|SSD_A_BY_ID|SSD_A_EXPECTED_MODEL|SSD_A_EXPECTED_SERIAL|SSD_A_MIN_BYTES|SSD_A_MAX_BYTES|SSD_A_ROLE|SSD_B_BY_ID|SSD_B_EXPECTED_MODEL|SSD_B_EXPECTED_SERIAL|SSD_B_MIN_BYTES|SSD_B_MAX_BYTES|SSD_B_ROLE)$'
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]] && continue
    [[ $line == *=* ]] || storage_fail 'manifest contains a malformed line'
    key=${line%%=*}
    value=${line#*=}
    [[ $key =~ $allowed ]] || storage_fail "manifest contains unsupported key: $key"
    [[ ! -v STORAGE_MANIFEST[$key] ]] || storage_fail "manifest repeats key: $key"
    # shellcheck disable=SC2016 # These are deliberately literal shell metacharacters.
    [[ $value != *'$('* && $value != *'`'* && $value != *$'\n'* ]] || \
      storage_fail "manifest value is unsafe: $key"
    STORAGE_MANIFEST[$key]=$value
  done <"$manifest"
  local required=(BACKUP_SET APPROVED_COMMIT EFI_SIZE_GIB WINDOWS_RESERVE_GIB
    OS_DISK_BY_ID OS_EXPECTED_MODEL OS_EXPECTED_SERIAL OS_MIN_BYTES OS_MAX_BYTES OS_ROLE
    SSD_A_BY_ID SSD_A_EXPECTED_MODEL SSD_A_EXPECTED_SERIAL SSD_A_MIN_BYTES SSD_A_MAX_BYTES SSD_A_ROLE
    SSD_B_BY_ID SSD_B_EXPECTED_MODEL SSD_B_EXPECTED_SERIAL SSD_B_MIN_BYTES SSD_B_MAX_BYTES SSD_B_ROLE)
  for key in "${required[@]}"; do
    [[ -n ${STORAGE_MANIFEST[$key]:-} ]] || storage_fail "manifest key is empty: $key"
  done
  [[ ${STORAGE_MANIFEST[EFI_SIZE_GIB]} == 10 && \
     ${STORAGE_MANIFEST[WINDOWS_RESERVE_GIB]} == 240 ]] || \
    storage_fail 'manifest layout constants must remain EFI=10 GiB and Windows reserve=240 GiB'
  [[ ${STORAGE_MANIFEST[OS_ROLE]} == helix-os && \
     ${STORAGE_MANIFEST[SSD_A_ROLE]} == helix-ssd-a && \
     ${STORAGE_MANIFEST[SSD_B_ROLE]} == helix-ssd-b ]] || storage_fail 'manifest roles are invalid'
  [[ ${STORAGE_MANIFEST[BACKUP_SET]} =~ ^helix-reinstall-[0-9]{8}-[0-9]{6}$ ]] || \
    storage_fail 'manifest backup set name is invalid'
  [[ ${STORAGE_MANIFEST[APPROVED_COMMIT]} =~ ^[0-9a-f]{40}$ ]] || \
    storage_fail 'manifest approved commit must be a full Git SHA'
  for key in OS_MIN_BYTES OS_MAX_BYTES SSD_A_MIN_BYTES SSD_A_MAX_BYTES SSD_B_MIN_BYTES SSD_B_MAX_BYTES; do
    [[ ${STORAGE_MANIFEST[$key]} =~ ^[0-9]+$ ]] || storage_fail "manifest size is invalid: $key"
  done
  [[ ${STORAGE_MANIFEST[OS_DISK_BY_ID]} != "${STORAGE_MANIFEST[SSD_A_BY_ID]}" && \
     ${STORAGE_MANIFEST[OS_DISK_BY_ID]} != "${STORAGE_MANIFEST[SSD_B_BY_ID]}" && \
     ${STORAGE_MANIFEST[SSD_A_BY_ID]} != "${STORAGE_MANIFEST[SSD_B_BY_ID]}" ]] || \
    storage_fail 'all three manifest targets must be distinct'
}

storage_device_record() {
  local by_id=$1
  if [[ ${HELIX_STORAGE_TEST_MODE:-0} == 1 ]]; then
    [[ -f ${HELIX_STORAGE_TEST_DEVICE_DB:-} ]] || storage_fail 'missing internal device fixture'
    awk -F '\t' -v id="$by_id" '$1 == id { print; found += 1 } END { if (found != 1) exit 1 }' \
      "$HELIX_STORAGE_TEST_DEVICE_DB" || storage_fail "fixture identity is not unique: $by_id"
    return
  fi
  [[ $by_id == /dev/disk/by-id/* && $by_id != *-part[0-9]* && -L $by_id ]] || \
    storage_fail "target is not a stable whole-disk by-id link: $by_id"
  local resolved type size rota removable model serial
  resolved=$(readlink -f -- "$by_id")
  [[ -b $resolved ]] || storage_fail "by-id target is not a block device: $by_id"
  type=$(lsblk -bdno TYPE "$resolved" | xargs)
  size=$(lsblk -bdno SIZE "$resolved" | xargs)
  rota=$(lsblk -bdno ROTA "$resolved" | xargs)
  removable=$(lsblk -bdno RM "$resolved" | xargs)
  model=$(lsblk -bdno MODEL "$resolved" | xargs)
  serial=$(lsblk -bdno SERIAL "$resolved" | xargs)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$by_id" "$resolved" "$type" "$size" "$rota" "$removable" "$model" "$serial" \
    "$(lsblk -nrpo UUID "$resolved" | paste -sd, - | sed 's/^$/-/')" \
    "$(lsblk -nrpo MOUNTPOINTS "$resolved" | sed '/^[[:space:]]*$/d' | paste -sd, - | sed 's/^$/-/')" \
    "$(storage_disk_has_holders "$resolved" && printf yes || printf no)" \
    "$(storage_is_installer_disk "$resolved" && printf yes || printf no)"
}

storage_disk_has_holders() {
  local disk=$1 node name
  while IFS= read -r node; do
    name=${node##*/}
    if compgen -G "/sys/class/block/$name/holders/*" >/dev/null; then return 0; fi
  done < <(lsblk -nrpo PATH "$disk")
  return 1
}

storage_parent_disk() {
  local node=$1 parent
  node=${node%%\[*}
  [[ -b $node ]] || return 1
  while parent=$(lsblk -dnro PKNAME "$node") && [[ -n $parent ]]; do node=/dev/$parent; done
  printf '%s\n' "$node"
}

storage_is_installer_disk() {
  local disk=$1 source parent
  for mount_path in / /iso /run/archiso/bootmnt; do
    source=$(findmnt -nro SOURCE --target "$mount_path" 2>/dev/null || true)
    parent=$(storage_parent_disk "$source" 2>/dev/null || true)
    [[ -n $parent && $parent == "$disk" ]] && return 0
  done
  return 1
}

storage_validate_target() {
  local prefix=$1 require_nonrotational=$2 record
  local byid_key=${prefix}_DISK_BY_ID
  [[ $prefix != OS ]] && byid_key=${prefix}_BY_ID
  record=$(storage_device_record "${STORAGE_MANIFEST[$byid_key]}")
  # These globals are the validated interface consumed by the dedicated callers.
  # shellcheck disable=SC2034
  IFS=$'\t' read -r TARGET_BY_ID TARGET_DISK TARGET_TYPE TARGET_SIZE TARGET_ROTA \
    TARGET_REMOVABLE TARGET_MODEL TARGET_SERIAL TARGET_UUIDS TARGET_MOUNTS \
    TARGET_HOLDERS TARGET_INSTALLER <<<"$record"
  [[ $TARGET_UUIDS == - ]] && TARGET_UUIDS=
  [[ $TARGET_MOUNTS == - ]] && TARGET_MOUNTS=
  [[ $TARGET_TYPE == disk ]] || storage_fail "$prefix target does not resolve to a whole disk"
  [[ $TARGET_MODEL == "${STORAGE_MANIFEST[${prefix}_EXPECTED_MODEL]}" ]] || \
    storage_fail "$prefix model does not match manifest"
  [[ $TARGET_SERIAL == "${STORAGE_MANIFEST[${prefix}_EXPECTED_SERIAL]}" ]] || \
    storage_fail "$prefix serial does not match manifest"
  ((TARGET_SIZE >= STORAGE_MANIFEST[${prefix}_MIN_BYTES] && \
    TARGET_SIZE <= STORAGE_MANIFEST[${prefix}_MAX_BYTES])) || storage_fail "$prefix size is outside manifest bounds"
  [[ $TARGET_REMOVABLE == 0 ]] || storage_fail "$prefix target is removable"
  [[ $require_nonrotational == false || $TARGET_ROTA == 0 ]] || storage_fail "$prefix target is rotational"
  [[ ,$TARGET_UUIDS, != *,${HELIX_GAMES_UUID},* ]] || storage_fail "$prefix contains protected GAMES_NVME"
  [[ -z $TARGET_MOUNTS ]] || storage_fail "$prefix contains mounted filesystems"
  [[ $TARGET_HOLDERS == no ]] || storage_fail "$prefix has active holders"
  [[ $TARGET_INSTALLER == no ]] || storage_fail "$prefix contains the installer environment"
  if [[ ${HELIX_STORAGE_TEST_MODE:-0} != 1 ]]; then
    local swap_source nas_source nas_disk
    nas_source=$(findmnt -nro SOURCE --target "$HELIX_NAS_MOUNT" 2>/dev/null || true)
    nas_disk=$(storage_parent_disk "$nas_source" 2>/dev/null || true)
    [[ -z $nas_disk || $nas_disk != "$TARGET_DISK" ]] || \
      storage_fail "$prefix contains the mounted NAS path"
    while read -r swap_source; do
      [[ -n $swap_source ]] || continue
      if lsblk -nrpo PATH "$TARGET_DISK" | grep -Fxq "$swap_source"; then
        storage_fail "$prefix contains active swap"
      fi
    done < <(swapon --show --noheadings --raw --output NAME)
  fi
}

storage_validate_three_distinct_resolved() {
  local os_record a_record b_record os_disk a_disk b_disk
  os_record=$(storage_device_record "${STORAGE_MANIFEST[OS_DISK_BY_ID]}")
  a_record=$(storage_device_record "${STORAGE_MANIFEST[SSD_A_BY_ID]}")
  b_record=$(storage_device_record "${STORAGE_MANIFEST[SSD_B_BY_ID]}")
  os_disk=$(cut -f2 <<<"$os_record"); a_disk=$(cut -f2 <<<"$a_record"); b_disk=$(cut -f2 <<<"$b_record")
  [[ $os_disk != "$a_disk" && $os_disk != "$b_disk" && $a_disk != "$b_disk" ]] || \
    storage_fail 'manifest by-id links do not resolve to three distinct disks'
}

storage_validate_backup() {
  if [[ ${HELIX_STORAGE_TEST_MODE:-0} == 1 ]]; then
    [[ ${HELIX_STORAGE_TEST_BACKUP_OK:-0} == 1 ]] || storage_fail 'completed backup validation is missing'
    return
  fi
  stat -- "$HELIX_NAS_MOUNT" >/dev/null
  mountpoint -q "$HELIX_NAS_MOUNT" || storage_fail 'NAS is not mounted'
  mapfile -t nas_sources < <(findmnt -rn --target "$HELIX_NAS_MOUNT" --types cifs -o SOURCE)
  [[ ${#nas_sources[@]} -eq 1 && ${nas_sources[0]%/} == "$HELIX_NAS_SOURCE" ]] || \
    storage_fail 'expected exactly one canonical CIFS layer beneath autofs'
  local set_path=$HELIX_BACKUP_ROOT/${STORAGE_MANIFEST[BACKUP_SET]}
  [[ -d $set_path && ! -L $set_path && -f $set_path/COMPLETE ]] || storage_fail 'completed backup set is absent'
  python3 "$HELIX_REPO_ROOT/scripts/validate-reinstall-restore.py" manifest "$set_path" >/dev/null
  python3 "$HELIX_REPO_ROOT/scripts/validate-reinstall-restore.py" archive "$set_path/home-tristan.tar" home/tristan >/dev/null
  python3 "$HELIX_REPO_ROOT/scripts/validate-reinstall-restore.py" archive "$set_path/etc-nixos-secrets.tar" etc/nixos/secrets >/dev/null
  (cd "$set_path" && sha256sum --check --strict SHA256SUMS >/dev/null) || storage_fail 'backup checksum validation failed'
}

storage_validate_repo() {
  HELIX_REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")/.." && pwd)
  local origin head
  origin=$(git -C "$HELIX_REPO_ROOT" remote get-url origin 2>/dev/null || true)
  head=$(git -C "$HELIX_REPO_ROOT" rev-parse HEAD 2>/dev/null || true)
  [[ $origin == https://github.com/tristanmcmahon/nixos-helix.git ]] || storage_fail 'repository origin is not canonical'
  [[ $head == "${STORAGE_MANIFEST[APPROVED_COMMIT]}" ]] || storage_fail 'checkout does not match approved commit'
  [[ $HELIX_REPO_ROOT == "$HELIX_CANONICAL_REPO" || $HELIX_REPO_ROOT == /tmp/nixos-helix-install ]] || \
    storage_fail 'checkout path is not approved'
}

storage_require_installer_environment() {
  [[ ${HELIX_STORAGE_TEST_MODE:-0} == 1 ]] && return
  [[ -d /sys/firmware/efi ]] || storage_fail 'installer was not booted through UEFI'
  local root_source root_type
  root_source=$(findmnt -nro SOURCE --mountpoint /)
  root_type=$(findmnt -nro FSTYPE --mountpoint /)
  [[ ! -b ${root_source%%\[*} && $root_type =~ ^(overlay|tmpfs|squashfs|iso9660)$ ]] || \
    storage_fail 'refusing to run from an installed block-backed root'
  [[ -e /etc/NIXOS || $(</proc/cmdline) == *helix.recovery=1* ]] || \
    storage_fail 'environment is not recognised NixOS installation media or approved recovery'
}

storage_print_disk() {
  local disk=$1
  lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL,SERIAL "$disk"
  if command -v sgdisk >/dev/null; then sgdisk --print "$disk" 2>/dev/null || true; fi
}
