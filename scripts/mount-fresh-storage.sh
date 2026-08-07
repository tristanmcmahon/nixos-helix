#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { printf 'Run this mount-only helper with sudo.\n' >&2; exit 1; }
games_uuid=d07ac88e-34f6-4d56-9941-5ceaf52fd6bb

unique_label() {
  local label=$1
  mapfile -t matches < <(blkid -t "LABEL=$label" -o device)
  [[ ${#matches[@]} -eq 1 ]] || { printf 'Expected exactly one %s filesystem.\n' "$label" >&2; exit 1; }
  printf '%s' "${matches[0]}"
}
safe_mount() {
  local source=$1 target=$2 options=${3:-}
  if mountpoint -q "$target"; then
    [[ $(findmnt -nro SOURCE --target "$target" | xargs readlink -f) == $(readlink -f "$source") ]] || {
      printf 'Conflicting mount at %s.\n' "$target" >&2; exit 1;
    }
    return
  fi
  install -d -m 0755 "$target"
  if [[ -n $options ]]; then mount -o "$options" "$source" "$target"; else mount "$source" "$target"; fi
}

games_device=$(blkid -U "$games_uuid" 2>/dev/null || true)
[[ -n $games_device ]] || { printf 'Protected GAMES_NVME UUID is absent.\n' >&2; exit 1; }
[[ $(blkid -s LABEL -o value "$games_device") == GAMES_NVME && \
   $(blkid -s TYPE -o value "$games_device") == ext4 ]] || {
  printf 'Protected GAMES_NVME label or filesystem type changed.\n' >&2; exit 1;
}
root=$(unique_label HELIX_ROOT); efi=$(unique_label HELIX_EFI)
safe_mount "$root" /mnt
safe_mount "$efi" /mnt/boot umask=0077
for suffix in A B; do
  label=HELIX_SSD_$suffix
  if blkid -t "LABEL=$label" -o device | grep -q .; then
    device=$(unique_label "$label")
    safe_mount "$device" "/mnt/mnt/helix_ssd_${suffix,,}"
  fi
done
allowed='^/mnt($|/boot$|/mnt/helix_ssd_(a|b)$)'
while IFS= read -r target; do
  [[ $target =~ $allowed ]] || { printf 'Unexpected mount beneath /mnt: %s\n' "$target" >&2; exit 1; }
done < <(findmnt -rn -o TARGET --submounts /mnt)
findmnt --submounts /mnt
lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINTS
