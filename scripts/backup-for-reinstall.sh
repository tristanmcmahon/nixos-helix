#!/usr/bin/env bash

set -euo pipefail

canonical_repo=/home/tristan/Projects/nixos-helix
nas_mount=/mnt/infernalnexus/nas1
backup_root=/mnt/infernalnexus/nas1/backup
expected_source=//192.168.1.8/nas1
backup_user=tristan

if [[ $# -ne 0 ]]; then
  printf 'Usage: %s\n' "${0##*/}" >&2
  exit 2
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $repo_root == "$canonical_repo" ]] || {
  printf 'FAIL: run the script from the canonical checkout: %s\n' "$canonical_repo" >&2
  exit 1
}
[[ $(pwd -P) == "$canonical_repo" ]] || {
  printf 'FAIL: change to %s before running this command.\n' "$canonical_repo" >&2
  exit 1
}

if [[ $EUID -ne 0 ]]; then
  exec sudo -- "$repo_root/scripts/backup-for-reinstall.sh"
fi

for command in blkid bootctl df findmnt git lsblk nix-env nixos-version \
  nix-store python3 runuser sha256sum ssh-keygen tar; do
  command -v "$command" >/dev/null || {
    printf 'FAIL: required command is unavailable: %s\n' "$command" >&2
    exit 1
  }
done

# These are the only machine-local /etc identities included. Refuse missing,
# linked, loosely protected, or unpaired inputs without displaying contents.
nm_profile=/etc/NetworkManager/system-connections/towerofdoom.nmconnection
[[ -f $nm_profile && ! -L $nm_profile ]] || {
  printf 'FAIL: required NetworkManager profile is absent or not a regular file.\n' >&2
  exit 1
}
[[ $(stat -c '%u:%g:%a' "$nm_profile") == 0:0:600 ]] || {
  printf 'FAIL: NetworkManager profile must be root:root mode 0600.\n' >&2
  exit 1
}
shopt -s nullglob
ssh_private_keys=(/etc/ssh/ssh_host_*_key)
ssh_public_keys=(/etc/ssh/ssh_host_*_key.pub)
shopt -u nullglob
(( ${#ssh_private_keys[@]} > 0 && ${#ssh_private_keys[@]} == ${#ssh_public_keys[@]} )) || {
  printf 'FAIL: SSH host keys are absent or not complete private/public pairs.\n' >&2
  exit 1
}
machine_identity_paths=(etc/NetworkManager/system-connections/towerofdoom.nmconnection)
for private_key in "${ssh_private_keys[@]}"; do
  public_key=$private_key.pub
  [[ -f $private_key && ! -L $private_key && -f $public_key && ! -L $public_key ]] || {
    printf 'FAIL: SSH host-key pair is incomplete or linked: %s\n' "${private_key##*/}" >&2
    exit 1
  }
  [[ $(stat -c '%u:%g:%a' "$private_key") == 0:0:600 && \
     $(stat -c '%u:%g:%a' "$public_key") == 0:0:644 ]] || {
    printf 'FAIL: SSH host-key metadata is unsafe: %s\n' "${private_key##*/}" >&2
    exit 1
  }
  machine_identity_paths+=("${private_key#/}" "${public_key#/}")
done
for public_key in "${ssh_public_keys[@]}"; do
  [[ -f ${public_key%.pub} ]] || {
    printf 'FAIL: SSH public host key has no private-key mate: %s\n' "${public_key##*/}" >&2
    exit 1
  }
done

# Access triggers the repository-owned systemd automount. Refuse a plain local
# directory even when it happens to exist at the same path.
stat -- "$nas_mount" >/dev/null
mountpoint -q "$nas_mount" || {
  printf 'FAIL: the canonical NAS path is not a mountpoint.\n' >&2
  exit 1
}
# A systemd automount produces stacked autofs and CIFS records for this exact
# path. Select the one real CIFS layer instead of comparing multi-line output.
mapfile -t nas_records < <(
  findmnt -rn --target "$nas_mount" --types cifs -o SOURCE,MAJ:MIN
)
[[ ${#nas_records[@]} -eq 1 ]] || {
  printf 'FAIL: expected exactly one CIFS layer at %s; found %s.\n' \
    "$nas_mount" "${#nas_records[@]}" >&2
  exit 1
}
read -r nas_source backup_device <<<"${nas_records[0]}"
# findmnt normally reports the configured //host/share spelling. A trailing
# slash is the only equivalent spelling accepted here.
[[ ${nas_source%/} == "$expected_source" ]] || {
  printf 'FAIL: unexpected NAS source at %s: %s\n' "$nas_mount" "$nas_source" >&2
  exit 1
}
[[ -d $backup_root ]] || {
  printf 'FAIL: the fixed backup directory does not exist: %s\n' "$backup_root" >&2
  exit 1
}
runuser -u "$backup_user" -- test -w "$backup_root" || {
  printf 'FAIL: %s is not writable by %s.\n' "$backup_root" "$backup_user" >&2
  exit 1
}

root_device=$(findmnt -nro MAJ:MIN --mountpoint /)
[[ -n $root_device && -n $backup_device && $root_device != "$backup_device" ]] || {
  printf 'FAIL: root and backup destination are not proven separate filesystems.\n' >&2
  exit 1
}

# The pre-run audit measured roughly 12 GiB under /home/tristan, including an
# 8.2 GiB Steam tree with 4.0 GiB of installed game/runtime payloads. Preserve
# Steam userdata and compatdata, but exclude installed/downloaded games,
# workshop payloads and shader caches. Recalculate conservatively every run.
home_bytes=$(du -sx --bytes --one-file-system /home/tristan | awk '{ print $1 }')
secrets_bytes=$(du -sx --bytes --one-file-system /etc/nixos/secrets | awk '{ print $1 }')
available_bytes=$(df --output=avail -B1 "$backup_root" | tail -n 1 | tr -d ' ')
required_bytes=$((home_bytes + secrets_bytes + home_bytes / 10 + 1024 * 1024 * 1024))
if (( available_bytes < required_bytes )); then
  printf 'FAIL: backup needs at least %s bytes; only %s are available.\n' \
    "$required_bytes" "$available_bytes" >&2
  exit 1
fi

timestamp=$(date -u +%Y%m%d-%H%M%S)
set_name=helix-reinstall-$timestamp
incomplete_path=$backup_root/$set_name.INCOMPLETE
final_path=$backup_root/$set_name
[[ ! -e $incomplete_path && ! -e $final_path ]] || {
  printf 'FAIL: backup set name already exists; wait one second and retry.\n' >&2
  exit 1
}
install -d -m 0755 "$incomplete_path"
printf 'An incomplete backup is retained on failure: %s\n' "$incomplete_path"

repo_head=$(git -C "$repo_root" rev-parse HEAD)
repo_branch=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || printf '(detached)')
origin_main=$(git -C "$repo_root" rev-parse origin/main)

git -C "$repo_root" rev-parse HEAD >"$incomplete_path/repository-head.txt"
git -C "$repo_root" rev-parse origin/main >"$incomplete_path/origin-main.txt"
printf '%s\n' "$repo_branch" >"$incomplete_path/repository-branch.txt"
git -C "$repo_root" status --short --branch >"$incomplete_path/repository-status.txt"
git -C "$repo_root" diff --binary >"$incomplete_path/repository-diff.patch"
git -C "$repo_root" diff --cached --binary >"$incomplete_path/repository-cached-diff.patch"
git -C "$repo_root" ls-files --others --exclude-standard \
  >"$incomplete_path/repository-untracked-files.txt"
install -m 0644 "$repo_root/hardware-configuration.nix" \
  "$incomplete_path/hardware-configuration-repository.nix"
install -m 0644 /etc/nixos/hardware-configuration.nix \
  "$incomplete_path/hardware-configuration-installed.nix"

lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,PARTUUID,MOUNTPOINTS,MODEL,SERIAL \
  >"$incomplete_path/lsblk.txt"
blkid >"$incomplete_path/blkid.txt"
findmnt --real >"$incomplete_path/findmnt.txt"
bootctl status >"$incomplete_path/bootctl-status.txt" 2>&1 || true
nixos-version >"$incomplete_path/nixos-version.txt"
uname -a >"$incomplete_path/uname.txt"
{
  printf 'running='
  readlink -f /run/current-system
  printf 'persistent='
  readlink -f /nix/var/nix/profiles/system
} >"$incomplete_path/system-closures.txt"
nix-env --profile /nix/var/nix/profiles/system --list-generations \
  >"$incomplete_path/nixos-generations.txt"
{
  printf 'System closure references:\n'
  nix-store --query --references "$(readlink -f /run/current-system)" | sort
  printf '\nUser profile packages:\n'
  runuser -u "$backup_user" -- nix-env --query --installed || true
} >"$incomplete_path/package-inventory.txt"
du -x -h --max-depth=1 /home/tristan | sort -h \
  >"$incomplete_path/home-size-audit.txt"

ssh_directory=no
authorized_keys_nonempty=no
private_key_files=0
if [[ -d /home/tristan/.ssh ]]; then
  ssh_directory=yes
  if [[ -s /home/tristan/.ssh/authorized_keys ]]; then
    authorized_keys_nonempty=yes
  fi
  private_key_files=$(
    { grep -IlRE --include='*' \
      '^-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----' \
      /home/tristan/.ssh 2>/dev/null || true; } | wc -l
  )
fi
printf '%s\n' \
  "ssh_directory=$ssh_directory" \
  "authorized_keys_nonempty=$authorized_keys_nonempty" \
  "private_key_shaped_files=$private_key_files" \
  >"$incomplete_path/ssh-metadata.txt"

tar --create --file="$incomplete_path/home-tristan.tar" \
  --one-file-system --numeric-owner --preserve-permissions --acls \
  --xattrs --xattrs-include='*' --selinux --sparse \
  --exclude='home/tristan/.cache' \
  --exclude='home/tristan/.local/share/Trash' \
  --exclude='home/tristan/Downloads/*.part' \
  --exclude='home/tristan/.local/share/Steam/steamapps/common' \
  --exclude='home/tristan/.local/share/Steam/steamapps/downloading' \
  --exclude='home/tristan/.local/share/Steam/steamapps/shadercache' \
  --exclude='home/tristan/.local/share/Steam/steamapps/workshop' \
  --exclude='home/tristan/.local/share/Steam/steamapps/compatdata/*/pfx/dosdevices' \
  --exclude='home/tristan/.local/share/Steam/steamrt64' \
  --exclude='home/tristan/.local/share/Steam/ubuntu12_32/steam-runtime' \
  --exclude='home/tristan/.local/share/Steam/ubuntu12_32/steam-runtime.old' \
  --exclude='home/tristan/.local/share/Steam/config/htmlcache' \
  --exclude='home/tristan/.codex/tmp' \
  --exclude='home/tristan/.config/Signal/Singleton*' \
  --exclude='home/tristan/.nix-profile' \
  --exclude='home/tristan/.nix-defexpr/channels_root' \
  --exclude='home/tristan/Projects/nixos-helix/result' \
  --directory=/ home/tristan
tar --create --file="$incomplete_path/etc-nixos-secrets.tar" \
  --one-file-system --numeric-owner --preserve-permissions --acls \
  --xattrs --xattrs-include='*' --selinux --sparse \
  --directory=/ etc/nixos/secrets
tar --create --file="$incomplete_path/machine-identity.tar" \
  --one-file-system --numeric-owner --preserve-permissions --acls \
  --xattrs --xattrs-include='*' --selinux --sparse \
  --directory=/ "${machine_identity_paths[@]}"
for public_key in "${ssh_public_keys[@]}"; do
  fingerprint=$(ssh-keygen -lf "$public_key" -E sha256 | awk '{ print $2 }')
  [[ $fingerprint == SHA256:* ]] || {
    printf 'FAIL: could not fingerprint SSH public host key: %s\n' "${public_key##*/}" >&2
    exit 1
  }
  printf '%s\t%s\n' "${public_key##*/}" "$fingerprint"
done >"$incomplete_path/ssh-host-key-fingerprints.txt"
chmod 0444 "$incomplete_path/ssh-host-key-fingerprints.txt"

cat >"$incomplete_path/BACKUP-README.txt" <<EOF
HELIX REINSTALL BACKUP

Created (UTC): $(date --utc --iso-8601=seconds)
Hostname: $(hostname)
Source machine: Helix
Destination share: $expected_source
Backup set: $final_path
Repository commit: $repo_head
Repository branch: $repo_branch
Origin/main: $origin_main

Archives:
  home-tristan.tar          /home/tristan, including dotfiles and Projects
  etc-nixos-secrets.tar     /etc/nixos/secrets (root access required)
  machine-identity.tar      exact NetworkManager profile and SSH host-key pairs

Machine identity scope (no other /etc content is included):
  /etc/NetworkManager/system-connections/towerofdoom.nmconnection
  /etc/ssh/ssh_host_*       complete public/private host-key pairs
  ssh-host-key-fingerprints.txt records public-key fingerprints for restore checks

Home exclusions:
  /home/tristan/.cache                 reproducible application caches
  /home/tristan/.local/share/Trash     desktop trash
  /home/tristan/Downloads/*.part       incomplete download fragments
  Steam steamapps/common                installed games and runtimes
  Steam steamapps/downloading           incomplete game downloads
  Steam steamapps/shadercache           reproducible shader caches
  Steam steamapps/workshop              downloadable workshop payloads
  Steam compatdata/*/pfx/dosdevices     host-specific Wine device links only
  Steam runtime and htmlcache trees     disposable downloaded/runtime material
  Codex temporary wrappers              disposable process-local links
  Signal Singleton* links               disposable process-local IPC state
  Nix profile/channel convenience links reproduced by Nix
  canonical repository result link      disposable Nix build output
  mounted filesystems                  tar --one-file-system safety boundary

Steam userdata, compatdata, configuration, screenshots and app manifests are
retained so local saves and reinstall metadata are not discarded.

The archives store Unix ownership, modes, ACLs, xattrs, SELinux metadata,
sparse files, hardlinks, and symlinks inside tar files because CIFS cannot
reliably represent all of that metadata as loose files.

Verification:
  cd "$final_path"
  sha256sum --check SHA256SUMS
  tar -tf home-tristan.tar >/dev/null
  sudo tar -tf etc-nixos-secrets.tar >/dev/null
  sudo tar -tf machine-identity.tar >/dev/null

Manually inspect this README, the inventories and repository patches. Extract
representative non-secret files into a temporary directory and open them.
Keep this backup until the fresh installation passes postflight. The boot
drive may be wiped only after manual inspection; COMPLETE is not permission
to erase a disk.
EOF

home_listing=$(mktemp)
checksum_manifest=$(mktemp)
trap 'rm -f -- "$home_listing" "$checksum_manifest"' EXIT
tar -tf "$incomplete_path/home-tristan.tar" >"$home_listing"
for expected_path in home/tristan/.config/ home/tristan/.ssh/ home/tristan/Projects/; do
  grep -Fxq "$expected_path" "$home_listing" || {
    printf 'FAIL: expected path is absent from the home archive: %s\n' "$expected_path" >&2
    exit 1
  }
done
tar -tf "$incomplete_path/etc-nixos-secrets.tar" >/dev/null
python3 "$repo_root/scripts/validate-reinstall-restore.py" archive \
  "$incomplete_path/home-tristan.tar" home/tristan >/dev/null
python3 "$repo_root/scripts/validate-reinstall-restore.py" archive \
  "$incomplete_path/etc-nixos-secrets.tar" etc/nixos/secrets >/dev/null
python3 "$repo_root/scripts/validate-reinstall-restore.py" machine-identity \
  "$incomplete_path/machine-identity.tar" >/dev/null
python3 "$repo_root/scripts/validate-reinstall-restore.py" fingerprints \
  "$incomplete_path/ssh-host-key-fingerprints.txt" \
  "$incomplete_path/machine-identity.tar" >/dev/null

(
  cd "$incomplete_path"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum \
    >"$checksum_manifest"
  sha256sum --check "$checksum_manifest"
  install -m 0444 "$checksum_manifest" SHA256SUMS
)
install -m 0444 /dev/null "$incomplete_path/COMPLETE"
mv --no-clobber -- "$incomplete_path" "$final_path"
[[ -d $final_path && ! -e $incomplete_path ]] || {
  printf 'FAIL: atomic promotion did not complete.\n' >&2
  exit 1
}
trap - EXIT
rm -f -- "$home_listing" "$checksum_manifest"

printf 'Completed backup: %s\n' "$final_path"
printf 'Verified: all checksums, three archives, dotfiles, SSH, and Projects.\n'
