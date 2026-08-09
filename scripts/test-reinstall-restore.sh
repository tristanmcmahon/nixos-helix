#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
restore_script=$repo_root/scripts/restore-after-reinstall.sh
test_base=$(mktemp -d)
trap 'rm -rf -- "$test_base"' EXIT
backup_root=$test_base/backup
target_home=$test_base/target-home
target_secrets=$test_base/target-secrets
target_nm_profile=$test_base/etc/NetworkManager/system-connections/towerofdoom.nmconnection
target_ssh_dir=$test_base/etc/ssh
report_root=$test_base/reports
staging_base=$test_base/staging
quarantine_root=$test_base/quarantine
mkdir -p "$backup_root" "$target_home" "$report_root" "$staging_base" "$quarantine_root"

artifact_names=(
  repository-head.txt origin-main.txt repository-branch.txt repository-status.txt
  repository-diff.patch repository-cached-diff.patch repository-untracked-files.txt
  hardware-configuration-repository.nix hardware-configuration-installed.nix
  lsblk.txt blkid.txt findmnt.txt bootctl-status.txt nixos-version.txt uname.txt
  system-closures.txt nixos-generations.txt package-inventory.txt
  home-size-audit.txt ssh-metadata.txt
)

rehash_set() {
  local backup_set=$1 temporary_manifest
  temporary_manifest=$(mktemp)
  (
    cd "$backup_set"
    find . -maxdepth 1 -type f ! -name COMPLETE ! -name SHA256SUMS -print0 |
      sort -z | xargs -0 sha256sum >"$temporary_manifest"
    mv -- "$temporary_manifest" SHA256SUMS
  )
}

make_set() {
  local name=$1 backup_set source
  backup_set=$backup_root/$name
  source=$test_base/source-$name
  mkdir -p "$source/home/tristan/.config" "$source/home/tristan/.ssh" \
    "$source/home/tristan/Projects" "$source/etc/nixos/secrets" \
    "$source/etc/NetworkManager/system-connections" "$source/etc/ssh" "$backup_set"
  printf 'shell profile\n' >"$source/home/tristan/.profile"
  printf 'project data\n' >"$source/home/tristan/Projects/notes.txt"
  ln -s /home/tristan/Projects "$source/home/tristan/projects-absolute"
  printf 'synthetic credential\n' >"$source/etc/nixos/secrets/infernalnexus-smb"
  chmod 0600 "$source/etc/nixos/secrets/infernalnexus-smb"
  printf 'synthetic NetworkManager fixture\n' \
    >"$source/etc/NetworkManager/system-connections/towerofdoom.nmconnection"
  chmod 0600 "$source/etc/NetworkManager/system-connections/towerofdoom.nmconnection"
  ssh-keygen -q -t ed25519 -N '' -f "$source/etc/ssh/ssh_host_ed25519_key"
  chmod 0600 "$source/etc/ssh/ssh_host_ed25519_key"
  chmod 0644 "$source/etc/ssh/ssh_host_ed25519_key.pub"
  tar -cf "$backup_set/home-tristan.tar" -C "$source" home/tristan
  tar -cf "$backup_set/etc-nixos-secrets.tar" -C "$source" etc/nixos/secrets
  tar -cf "$backup_set/machine-identity.tar" -C "$source" \
    etc/NetworkManager/system-connections/towerofdoom.nmconnection \
    etc/ssh/ssh_host_ed25519_key etc/ssh/ssh_host_ed25519_key.pub
  printf 'ssh_host_ed25519_key.pub\t%s\n' \
    "$(ssh-keygen -lf "$source/etc/ssh/ssh_host_ed25519_key.pub" -E sha256 | awk '{ print $2 }')" \
    >"$backup_set/ssh-host-key-fingerprints.txt"
  printf '%s\n' \
    'HELIX REINSTALL BACKUP' \
    'Created (UTC): 2026-08-06T00:00:00+00:00' \
    'Hostname: synthetic' \
    'Source machine: test' \
    'Destination share: //192.168.1.8/nas1' \
    'Repository commit: synthetic' >"$backup_set/BACKUP-README.txt"
  for artifact in "${artifact_names[@]}"; do
    printf 'synthetic inventory\n' >"$backup_set/$artifact"
  done
  rehash_set "$backup_set"
  : >"$backup_set/COMPLETE"
}

run_restore() {
  env \
    HELIX_RESTORE_TEST_MODE=1 \
    HELIX_RESTORE_TEST_BASE="$test_base" \
    HELIX_RESTORE_TEST_BACKUP_ROOT="$backup_root" \
    HELIX_RESTORE_TEST_HOME="$target_home" \
    HELIX_RESTORE_TEST_SECRETS="$target_secrets" \
    HELIX_RESTORE_TEST_NM_PROFILE="$target_nm_profile" \
    HELIX_RESTORE_TEST_SSH_DIR="$target_ssh_dir" \
    HELIX_RESTORE_TEST_REPORT_ROOT="$report_root" \
    HELIX_RESTORE_TEST_STAGING_BASE="$staging_base" \
    HELIX_RESTORE_TEST_QUARANTINE_ROOT="$quarantine_root" \
    "$restore_script" "$@"
}

tree_checksum() {
  local root=$1
  (
    cd "$root"
    find . -type f -print0 | sort -z | xargs -0 sha256sum
  ) | sha256sum | awk '{ print $1 }'
}

valid_name=helix-reinstall-20260806-154900
make_set "$valid_name"
backup_before=$(tree_checksum "$backup_root/$valid_name")
home_before=$(tree_checksum "$target_home")
plan_output=$(run_restore "$valid_name")
grep -qF 'HELIX CANONICAL RESTORE — VALIDATED PLAN' <<<"$plan_output"
grep -qF 'Manifest: verified' <<<"$plan_output"
grep -qF 'Machine identity archive: verified' <<<"$plan_output"
grep -qF "Home ownership: archived $(id -u):$(id -g); target $(id -u):$(id -g)" \
  <<<"$plan_output"
grep -qF 'No changes made.' <<<"$plan_output"
[[ $(tree_checksum "$target_home") == "$home_before" ]]
[[ $(tree_checksum "$backup_root/$valid_name") == "$backup_before" ]]

missing_complete=helix-reinstall-20260806-154901
cp -a "$backup_root/$valid_name" "$backup_root/$missing_complete"
rm "$backup_root/$missing_complete/COMPLETE"
if run_restore "$missing_complete" >/dev/null 2>&1; then
  printf 'Restore accepted a set without COMPLETE.\n' >&2
  exit 1
fi

missing_archive=helix-reinstall-20260806-154902
cp -a "$backup_root/$valid_name" "$backup_root/$missing_archive"
rm "$backup_root/$missing_archive/home-tristan.tar"
if run_restore "$missing_archive" >/dev/null 2>&1; then
  printf 'Restore accepted a missing archive.\n' >&2
  exit 1
fi

bad_checksum=helix-reinstall-20260806-154903
cp -a "$backup_root/$valid_name" "$backup_root/$bad_checksum"
printf 'changed\n' >>"$backup_root/$bad_checksum/lsblk.txt"
if run_restore "$bad_checksum" >/dev/null 2>&1; then
  printf 'Restore accepted a bad checksum.\n' >&2
  exit 1
fi

for invalid_name in /tmp/backup ../backup backup/name helix-reinstall-latest; do
  if run_restore "$invalid_name" >/dev/null 2>&1; then
    printf 'Restore accepted invalid set name: %s\n' "$invalid_name" >&2
    exit 1
  fi
done

make_malicious_home_archive() {
  local archive=$1 kind=$2
  python3 - "$archive" "$kind" <<'PY'
import io
import sys
import tarfile

archive, kind = sys.argv[1:]
with tarfile.open(archive, "w") as handle:
    for name in ("home/tristan", "home/tristan/.config", "home/tristan/.ssh", "home/tristan/Projects"):
        member = tarfile.TarInfo(name)
        member.type = tarfile.DIRTYPE
        member.mode = 0o755
        handle.addfile(member)
    if kind == "absolute":
        member = tarfile.TarInfo("/etc/passwd")
        member.size = 1
        handle.addfile(member, io.BytesIO(b"x"))
    elif kind == "traversal":
        member = tarfile.TarInfo("home/tristan/../../escape")
        member.size = 1
        handle.addfile(member, io.BytesIO(b"x"))
    elif kind == "symlink":
        member = tarfile.TarInfo("home/tristan/escape-link")
        member.type = tarfile.SYMTYPE
        member.linkname = "../../../escape"
        handle.addfile(member)
    elif kind == "absolute-symlink":
        member = tarfile.TarInfo("home/tristan/escape-absolute-link")
        member.type = tarfile.SYMTYPE
        member.linkname = "/etc"
        handle.addfile(member)
    elif kind == "hardlink":
        member = tarfile.TarInfo("home/tristan/escape-hardlink")
        member.type = tarfile.LNKTYPE
        member.linkname = "../../escape"
        handle.addfile(member)
PY
}

index=4
for malicious_kind in absolute traversal symlink absolute-symlink hardlink; do
  printf -v malicious_name 'helix-reinstall-20260806-1549%02d' "$index"
  cp -a "$backup_root/$valid_name" "$backup_root/$malicious_name"
  make_malicious_home_archive "$backup_root/$malicious_name/home-tristan.tar" "$malicious_kind"
  rehash_set "$backup_root/$malicious_name"
  if run_restore "$malicious_name" >/dev/null 2>&1; then
    printf 'Restore accepted unsafe %s archive.\n' "$malicious_kind" >&2
    exit 1
  fi
  ((index += 1))
done

missing_pair=helix-reinstall-20260806-154910
cp -a "$backup_root/$valid_name" "$backup_root/$missing_pair"
tar --delete --file="$backup_root/$missing_pair/machine-identity.tar" \
  etc/ssh/ssh_host_ed25519_key.pub
rehash_set "$backup_root/$missing_pair"
if run_restore "$missing_pair" >/dev/null 2>&1; then
  printf 'Restore accepted an incomplete SSH host-key pair.\n' >&2
  exit 1
fi

broadened_etc=helix-reinstall-20260806-154911
cp -a "$backup_root/$valid_name" "$backup_root/$broadened_etc"
printf 'unexpected fixture\n' >"$test_base/source-$valid_name/etc/unrelated.conf"
tar --append --file="$backup_root/$broadened_etc/machine-identity.tar" \
  -C "$test_base/source-$valid_name" etc/unrelated.conf
rehash_set "$backup_root/$broadened_etc"
if run_restore "$broadened_etc" >/dev/null 2>&1; then
  printf 'Restore accepted unrelated /etc content in machine identity.\n' >&2
  exit 1
fi

mismatched_owner=helix-reinstall-20260806-154912
cp -a "$backup_root/$valid_name" "$backup_root/$mismatched_owner"
tar --create --file="$backup_root/$mismatched_owner/home-tristan.tar" \
  --owner="$(( $(id -u) + 1 ))" --group="$(id -g)" \
  --directory="$test_base/source-$valid_name" home/tristan
rehash_set "$backup_root/$mismatched_owner"
home_before_mismatch=$(tree_checksum "$target_home")
if run_restore "$mismatched_owner" >/dev/null 2>&1; then
  printf 'Restore accepted a mismatched archived home UID.\n' >&2
  exit 1
fi
[[ $(tree_checksum "$target_home") == "$home_before_mismatch" ]]

printf 'existing data\n' >"$target_home/personal-document.txt"
reports_before=$(find "$report_root" -type f | wc -l)
if HELIX_RESTORE_TEST_CONFIRMATION="RESTORE $valid_name" \
  run_restore "$valid_name" --run >/dev/null 2>&1; then
  printf 'Restore accepted a materially populated home without override.\n' >&2
  exit 1
fi
[[ $(find "$report_root" -type f | wc -l) == "$reports_before" ]]
rm "$target_home/personal-document.txt"

printf 'old profile\n' >"$target_home/.profile"
collision_plan=$(run_restore "$valid_name")
grep -qF 'Home collisions: 1' <<<"$collision_plan"
grep -qF 'Exact minimal-home collision roots:' <<<"$collision_plan"
grep -qF '  .profile' <<<"$collision_plan"

mkdir -p "$target_ssh_dir"
printf 'unrelated SSH configuration fixture\n' >"$target_ssh_dir/sshd_config"
ssh-keygen -q -t rsa -N '' -f "$target_ssh_dir/ssh_host_rsa_key"

backup_before_restore=$(tree_checksum "$backup_root/$valid_name")
HELIX_RESTORE_TEST_CONFIRMATION="RESTORE $valid_name" \
  run_restore "$valid_name" --run >/dev/null
[[ $(stat -c '%a' "$target_secrets/infernalnexus-smb") == 600 ]]
[[ $(stat -c '%u:%g' "$target_secrets/infernalnexus-smb") == "$(id -u):$(id -g)" ]]
[[ $(stat -c '%u:%g:%a' "$target_nm_profile") == "$(id -u):$(id -g):600" ]]
[[ -f $target_ssh_dir/ssh_host_ed25519_key ]]
[[ -f $target_ssh_dir/ssh_host_ed25519_key.pub ]]
[[ ! -e $target_ssh_dir/ssh_host_rsa_key ]]
[[ ! -e $target_ssh_dir/ssh_host_rsa_key.pub ]]
grep -qxF 'unrelated SSH configuration fixture' "$target_ssh_dir/sshd_config"
expected_fingerprint=$(cut -f2 "$backup_root/$valid_name/ssh-host-key-fingerprints.txt")
actual_fingerprint=$(ssh-keygen -lf "$target_ssh_dir/ssh_host_ed25519_key.pub" -E sha256 | awk '{ print $2 }')
[[ $actual_fingerprint == "$expected_fingerprint" ]]
[[ -f $target_home/Projects/notes.txt ]]
[[ $(readlink "$target_home/projects-absolute") == /home/tristan/Projects ]]
[[ $(find "$report_root" -name 'restore-*.txt' -type f | wc -l) == 1 ]]
[[ $(tree_checksum "$backup_root/$valid_name") == "$backup_before_restore" ]]

grep -qxF 'backup_root=/mnt/infernalnexus/nas1/backup' "$restore_script"
grep -qF "findmnt -rn --target \"\$nas_mount\" --types cifs" "$restore_script"
if grep -Eq '\b(mkfs|parted|fdisk|sgdisk|wipefs)\b' "$restore_script"; then
  printf 'A destructive storage command entered the restore script.\n' >&2
  exit 1
fi
printf 'Canonical reinstall restore tests passed.\n'
