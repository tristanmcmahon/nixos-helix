#!/usr/bin/env bash

set -euo pipefail

canonical_repo=/home/tristan/Projects/nixos-helix
nas_mount=/mnt/infernalnexus/nas1
backup_root=/mnt/infernalnexus/nas1/backup
expected_source=//192.168.1.8/nas1
target_home=/home/tristan
target_secrets=/etc/nixos/secrets
target_nm_profile=/etc/NetworkManager/system-connections/towerofdoom.nmconnection
target_ssh_dir=/etc/ssh
report_root=/var/lib/helix-install
staging_base=/var/tmp
quarantine_root=/var/lib/helix-install
test_mode=${HELIX_RESTORE_TEST_MODE:-0}

usage() {
  printf 'Usage: %s BACKUP_SET [--run [--merge-existing-home]]\n' "${0##*/}" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 3 ]] || usage
set_name=$1
run_restore=false
merge_existing=false
shift
while (( $# > 0 )); do
  case $1 in
  --run)
    [[ $run_restore == false ]] || usage
    run_restore=true
    ;;
  --merge-existing-home)
    [[ $merge_existing == false ]] || usage
    merge_existing=true
    ;;
  *) usage ;;
  esac
  shift
done
[[ $merge_existing == false || $run_restore == true ]] || usage
[[ $set_name =~ ^helix-reinstall-[0-9]{8}-[0-9]{6}$ ]] || {
  printf 'FAIL: BACKUP_SET must be a canonical backup-set basename.\n' >&2
  exit 1
}
[[ $set_name != *..* && $set_name != */* && $set_name != /* ]] || {
  printf 'FAIL: BACKUP_SET must not contain a path.\n' >&2
  exit 1
}

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
validator=$repo_root/scripts/validate-reinstall-restore.py
for command in python3 sha256sum ssh-keygen tar; do
  command -v "$command" >/dev/null || {
    printf 'FAIL: required command is unavailable: %s\n' "$command" >&2
    exit 1
  }
done
[[ $repo_root == "$canonical_repo" || $test_mode == 1 ]] || {
  printf 'FAIL: use the canonical checkout at %s.\n' "$canonical_repo" >&2
  exit 1
}

if [[ $test_mode == 1 ]]; then
  test_base=${HELIX_RESTORE_TEST_BASE:-}
  [[ -n $test_base && $test_base == /tmp/* && -d $test_base ]] || {
    printf 'FAIL: invalid internal restore-test base.\n' >&2
    exit 1
  }
  for variable in HELIX_RESTORE_TEST_BACKUP_ROOT HELIX_RESTORE_TEST_HOME \
    HELIX_RESTORE_TEST_SECRETS HELIX_RESTORE_TEST_REPORT_ROOT \
    HELIX_RESTORE_TEST_STAGING_BASE HELIX_RESTORE_TEST_QUARANTINE_ROOT \
    HELIX_RESTORE_TEST_NM_PROFILE HELIX_RESTORE_TEST_SSH_DIR; do
    value=${!variable:-}
    [[ -n $value && $(realpath -m -- "$value") == "$test_base"/* ]] || {
      printf 'FAIL: invalid internal restore-test path.\n' >&2
      exit 1
    }
  done
  backup_root=$HELIX_RESTORE_TEST_BACKUP_ROOT
  target_home=$HELIX_RESTORE_TEST_HOME
  target_secrets=$HELIX_RESTORE_TEST_SECRETS
  target_nm_profile=$HELIX_RESTORE_TEST_NM_PROFILE
  target_ssh_dir=$HELIX_RESTORE_TEST_SSH_DIR
  report_root=$HELIX_RESTORE_TEST_REPORT_ROOT
  staging_base=$HELIX_RESTORE_TEST_STAGING_BASE
  quarantine_root=$HELIX_RESTORE_TEST_QUARANTINE_ROOT
elif env | grep -q '^HELIX_RESTORE_TEST_'; then
  printf 'FAIL: internal restore-test settings require test mode.\n' >&2
  exit 1
fi

if [[ $run_restore == true && $test_mode != 1 ]]; then
  [[ -t 0 && -t 1 ]] || {
    printf 'FAIL: --run requires an interactive terminal.\n' >&2
    exit 1
  }
  if [[ $EUID -ne 0 ]]; then
    arguments=("$set_name" --run)
    [[ $merge_existing == true ]] && arguments+=(--merge-existing-home)
    exec sudo -- "$repo_root/scripts/restore-after-reinstall.sh" "${arguments[@]}"
  fi
fi

if [[ $test_mode != 1 ]]; then
  stat -- "$nas_mount" >/dev/null
  mountpoint -q "$nas_mount" || {
    printf 'FAIL: the canonical NAS path is not a mountpoint.\n' >&2
    exit 1
  }
  # systemd exposes stacked autofs and CIFS records. Select exactly one real
  # CIFS layer; never compare the combined multi-line filesystem-type output.
  mapfile -t nas_sources < <(
    findmnt -rn --target "$nas_mount" --types cifs -o SOURCE
  )
  [[ ${#nas_sources[@]} -eq 1 ]] || {
    printf 'FAIL: expected exactly one CIFS layer at %s; found %s.\n' \
      "$nas_mount" "${#nas_sources[@]}" >&2
    exit 1
  }
  [[ ${nas_sources[0]%/} == "$expected_source" ]] || {
    printf 'FAIL: the mounted CIFS source is not %s.\n' "$expected_source" >&2
    exit 1
  }
fi

backup_set=$backup_root/$set_name
[[ -d $backup_set && ! -L $backup_set ]] || {
  printf 'FAIL: selected backup set is missing, not a directory, or a symlink.\n' >&2
  exit 1
}
[[ $(realpath -e -- "$backup_set") == "$(realpath -e -- "$backup_root")/$set_name" ]] || {
  printf 'FAIL: selected backup set is not directly beneath the fixed root.\n' >&2
  exit 1
}

required_files=(
  COMPLETE SHA256SUMS BACKUP-README.txt home-tristan.tar etc-nixos-secrets.tar
  machine-identity.tar ssh-host-key-fingerprints.txt
  repository-head.txt origin-main.txt repository-branch.txt repository-status.txt
  repository-diff.patch repository-cached-diff.patch repository-untracked-files.txt
  hardware-configuration-repository.nix hardware-configuration-installed.nix
  lsblk.txt blkid.txt findmnt.txt bootctl-status.txt nixos-version.txt uname.txt
  system-closures.txt nixos-generations.txt package-inventory.txt
  home-size-audit.txt ssh-metadata.txt
)
for required_file in "${required_files[@]}"; do
  [[ -f $backup_set/$required_file && ! -L $backup_set/$required_file ]] || {
    printf 'FAIL: required backup artifact is missing or a symlink: %s\n' \
      "$required_file" >&2
    exit 1
  }
done

manifest_entries=$(python3 "$validator" manifest "$backup_set")
(
  cd "$backup_set"
  sha256sum --check --strict SHA256SUMS >/dev/null
) || {
  printf 'FAIL: backup checksum verification failed.\n' >&2
  exit 1
}
manifest_checksum=$(sha256sum "$backup_set/SHA256SUMS" | awk '{ print $1 }')
read -r home_entries home_bytes < <(
  python3 "$validator" archive "$backup_set/home-tristan.tar" home/tristan
)
read -r secrets_entries secrets_bytes < <(
  python3 "$validator" archive "$backup_set/etc-nixos-secrets.tar" etc/nixos/secrets
)
read -r archived_home_uid archived_home_gid < <(
  python3 "$validator" root-owner "$backup_set/home-tristan.tar" home/tristan
)
if [[ $test_mode == 1 ]]; then
  target_home_uid=$(id -u)
  target_home_gid=$(id -g)
else
  target_home_uid=$(id -u tristan)
  target_home_gid=$(id -g tristan)
fi
[[ $archived_home_uid == "$target_home_uid" && \
   $archived_home_gid == "$target_home_gid" ]] || {
  printf 'FAIL: archived home owner %s:%s does not match Tristan target %s:%s.\n' \
    "$archived_home_uid" "$archived_home_gid" "$target_home_uid" "$target_home_gid" >&2
  exit 1
}
expected_identity_uid=0
expected_identity_gid=0
if [[ $test_mode == 1 ]]; then
  expected_identity_uid=$(id -u)
  expected_identity_gid=$(id -g)
fi
read -r identity_entries identity_bytes ssh_pair_count < <(
  python3 "$validator" machine-identity "$backup_set/machine-identity.tar" \
    "$expected_identity_uid" "$expected_identity_gid"
)
fingerprint_count=$(python3 "$validator" fingerprints \
  "$backup_set/ssh-host-key-fingerprints.txt" "$backup_set/machine-identity.tar" \
  "$expected_identity_uid" "$expected_identity_gid")

mapfile -t home_collision_output < <(
  python3 "$validator" collisions "$backup_set/home-tristan.tar" \
    home/tristan "$target_home"
)
home_collisions=${home_collision_output[0]:-0}
home_collision_names=("${home_collision_output[@]:1}")
home_collision_display=()
canonical_repo_collision=false
for collision_name in "${home_collision_names[@]}"; do
  case $collision_name in
  Projects/nixos-helix | Projects/nixos-helix/*)
    if [[ $canonical_repo_collision == false ]]; then
      home_collision_display+=("Projects/nixos-helix (canonical checkout subtree)")
      canonical_repo_collision=true
    fi
    ;;
  *) home_collision_display+=("$collision_name") ;;
  esac
done
mapfile -t secret_collision_output < <(
  python3 "$validator" collisions "$backup_set/etc-nixos-secrets.tar" \
    etc/nixos/secrets "$target_secrets"
)
secret_collisions=${secret_collision_output[0]:-0}

home_state=minimal
material_entries=()
if [[ -d $target_home ]]; then
  while IFS= read -r entry; do
    case $entry in
    .bash_profile | .bashrc | .profile | .zshrc) ;;
    Projects)
      mapfile -t project_entries < <(
        find "$target_home/Projects" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort
      )
      if (( ${#project_entries[@]} != 1 )) || [[ ${project_entries[0]:-} != nixos-helix ]]; then
        material_entries+=(Projects)
      fi
      ;;
    *) material_entries+=("$entry") ;;
    esac
  done < <(find "$target_home" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort)
fi
if (( ${#material_entries[@]} > 0 )); then
  home_state=materially-populated
fi

graphical_session=no
if [[ $test_mode != 1 ]] && command -v loginctl >/dev/null; then
  while read -r session_id _ session_user _; do
    [[ $session_user == tristan ]] || continue
    session_type=$(loginctl show-session "$session_id" -p Type --value 2>/dev/null || true)
    session_active=$(loginctl show-session "$session_id" -p Active --value 2>/dev/null || true)
    if [[ $session_active == yes && $session_type =~ ^(wayland|x11)$ ]]; then
      graphical_session=yes
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
fi

printf '%s\n' \
  'HELIX CANONICAL RESTORE — VALIDATED PLAN' \
  "Backup set: $set_name" \
  "Backup root: $backup_root"
grep -E '^(Created \(UTC\)|Hostname|Source machine|Destination share|Repository commit):' \
  "$backup_set/BACKUP-README.txt" || true
printf '%s\n' \
  "Manifest: verified ($manifest_entries artifacts, SHA256 $manifest_checksum)" \
  "Home archive: verified ($home_entries paths, approximately $home_bytes data bytes)" \
  "Home ownership: archived $archived_home_uid:$archived_home_gid; target $target_home_uid:$target_home_gid" \
  "Secrets archive: verified ($secrets_entries paths, approximately $secrets_bytes data bytes)" \
  "Machine identity archive: verified ($identity_entries files, approximately $identity_bytes data bytes, $ssh_pair_count SSH pairs)" \
  "Recorded SSH fingerprints: verified ($fingerprint_count public keys)" \
  "Restore target: $target_home ($home_state)" \
  "Secrets target: $target_secrets" \
  "NetworkManager identity target: $target_nm_profile" \
  "SSH host-key target: $target_ssh_dir/ssh_host_*" \
  "Home collisions: $home_collisions" \
  "Secrets collisions: $secret_collisions" \
  "Active Tristan graphical session: $graphical_session"
if [[ -d $target_secrets ]]; then
  printf 'Existing secrets directory metadata: '
  stat -c '%U:%G %a' "$target_secrets" 2>/dev/null || printf 'not readable without root\n'
else
  printf 'Existing secrets directory: absent\n'
fi
if (( home_collisions > 0 )); then
  if [[ $home_state == minimal ]]; then
    printf 'Exact minimal-home collision roots:\n'
    printf '  %s\n' "${home_collision_display[@]}"
  else
    printf 'Material-home collision sample (up to 20 of %s):\n' "$home_collisions"
    printf '  %s\n' "${home_collision_names[@]:0:20}"
  fi
fi
printf '%s\n' \
  'Will restore home, NixOS secrets, the exact NetworkManager profile, and SSH host-key pairs from separate staged archives.' \
  'Hardware inventories, UUID configuration, boot state, Nix profiles and closures remain reference-only.'

if [[ $run_restore == false ]]; then
  printf 'No changes made. Exact execution command:\n  %q %q --run\n' "$0" "$set_name"
  if [[ $home_state == materially-populated ]]; then
    printf 'Material home requires the potentially destructive reviewed override:\n'
    printf '  %q %q --run --merge-existing-home\n' "$0" "$set_name"
  fi
  exit 0
fi

[[ $graphical_session == no ]] || {
  printf "FAIL: log out of Tristan's graphical session and restore from a text console.\n" >&2
  exit 1
}
if [[ $home_state == materially-populated && $merge_existing == false ]]; then
  printf 'FAIL: refusing to restore over a materially populated home.\n' >&2
  exit 1
fi

confirmation=
if [[ $test_mode == 1 ]]; then
  confirmation=${HELIX_RESTORE_TEST_CONFIRMATION:-}
else
  printf 'Type exactly: RESTORE %s\n> ' "$set_name"
  IFS= read -r confirmation
fi
[[ $confirmation == "RESTORE $set_name" ]] || {
  printf 'FAIL: restore confirmation did not match.\n' >&2
  exit 1
}
if [[ $home_state == materially-populated ]]; then
  merge_confirmation=
  if [[ $test_mode == 1 ]]; then
    merge_confirmation=${HELIX_RESTORE_TEST_MERGE_CONFIRMATION:-}
  else
    printf 'Type exactly: MERGE EXISTING HOME %s\n> ' "$set_name"
    IFS= read -r merge_confirmation
  fi
  [[ $merge_confirmation == "MERGE EXISTING HOME $set_name" ]] || {
    printf 'FAIL: merge confirmation did not match.\n' >&2
    exit 1
  }
fi

install -d -m 0700 "$staging_base" "$report_root" "$quarantine_root"
staging=$(mktemp -d --tmpdir="$staging_base" \
  "helix-restore-$set_name.INCOMPLETE.XXXXXX")
chmod 0700 "$staging"
restore_succeeded=false
trap 'if [[ $restore_succeeded == false ]]; then printf "Restore failed; staging retained at %s\n" "$staging" >&2; fi' EXIT

tar --extract --file="$backup_set/home-tristan.tar" --directory="$staging" \
  --numeric-owner --same-owner --same-permissions --acls --xattrs \
  --xattrs-include='*' --selinux --sparse --delay-directory-restore
tar --extract --file="$backup_set/etc-nixos-secrets.tar" --directory="$staging" \
  --numeric-owner --same-owner --same-permissions --acls --xattrs \
  --xattrs-include='*' --selinux --sparse --delay-directory-restore
tar --extract --file="$backup_set/machine-identity.tar" --directory="$staging" \
  --numeric-owner --same-owner --same-permissions --acls --xattrs \
  --xattrs-include='*' --selinux --sparse --delay-directory-restore
staged_entries=$(python3 "$validator" staged "$staging")
staged_home_uid=$(stat -c '%u' "$staging/home/tristan")
staged_home_gid=$(stat -c '%g' "$staging/home/tristan")
[[ $staged_home_uid == "$target_home_uid" && $staged_home_gid == "$target_home_gid" ]] || {
  printf 'FAIL: staged home owner %s:%s does not match Tristan target %s:%s.\n' \
    "$staged_home_uid" "$staged_home_gid" "$target_home_uid" "$target_home_gid" >&2
  exit 1
}

staged_nm=$staging/etc/NetworkManager/system-connections/towerofdoom.nmconnection
[[ -f $staged_nm && ! -L $staged_nm ]] || {
  printf 'FAIL: staged NetworkManager profile is absent or unsafe.\n' >&2
  exit 1
}
[[ $(stat -c '%u:%g:%a' "$staged_nm") == \
   "$expected_identity_uid:$expected_identity_gid:600" ]] || {
  printf 'FAIL: staged NetworkManager profile ownership or mode is unsafe.\n' >&2
  exit 1
}
expected_ssh_files=()
while IFS=$'\t' read -r key_name expected_fingerprint; do
  staged_public=$staging/etc/ssh/$key_name
  staged_private=${staged_public%.pub}
  expected_ssh_files+=("${key_name%.pub}" "$key_name")
  [[ -f $staged_public && ! -L $staged_public && -f $staged_private && ! -L $staged_private ]] || {
    printf 'FAIL: staged SSH host-key pair is incomplete.\n' >&2
    exit 1
  }
  [[ $(stat -c '%u:%g:%a' "$staged_private") == \
     "$expected_identity_uid:$expected_identity_gid:600" && \
     $(stat -c '%u:%g:%a' "$staged_public") == \
     "$expected_identity_uid:$expected_identity_gid:644" ]] || {
    printf 'FAIL: staged SSH host-key ownership or mode is unsafe.\n' >&2
    exit 1
  }
  actual_fingerprint=$(ssh-keygen -lf "$staged_public" -E sha256 | awk '{ print $2 }')
  [[ $actual_fingerprint == "$expected_fingerprint" ]] || {
    printf 'FAIL: staged SSH public-key fingerprint differs from the preinstall record.\n' >&2
    exit 1
  }
done <"$backup_set/ssh-host-key-fingerprints.txt"

quarantine=none
if (( home_collisions > 0 || secret_collisions > 0 )) || \
   [[ -e $target_nm_profile ]] || compgen -G "$target_ssh_dir/ssh_host_*" >/dev/null; then
  quarantine=$quarantine_root/quarantine-restore-$(date -u +%Y%m%d-%H%M%S)
  install -d -m 0700 "$quarantine"
  if [[ -d $target_home ]]; then
    tar --create --file="$quarantine/home-tristan.before.tar" \
      --one-file-system --numeric-owner --preserve-permissions --acls \
      --xattrs --xattrs-include='*' --selinux --sparse \
      --directory="$(dirname -- "$target_home")" "$(basename -- "$target_home")"
    chmod 0600 "$quarantine/home-tristan.before.tar"
  fi
  if [[ -d $target_secrets ]]; then
    tar --create --file="$quarantine/etc-nixos-secrets.before.tar" \
      --one-file-system --numeric-owner --preserve-permissions --acls \
      --xattrs --xattrs-include='*' --selinux --sparse \
      --directory="$(dirname -- "$target_secrets")" "$(basename -- "$target_secrets")"
    chmod 0600 "$quarantine/etc-nixos-secrets.before.tar"
  fi
  existing_identity=()
  [[ -e $target_nm_profile ]] && existing_identity+=("${target_nm_profile#/}")
  shopt -s nullglob
  for existing_key in "$target_ssh_dir"/ssh_host_*; do
    existing_identity+=("${existing_key#/}")
  done
  shopt -u nullglob
  if (( ${#existing_identity[@]} > 0 )); then
    tar --create --file="$quarantine/machine-identity.before.tar" \
      --one-file-system --numeric-owner --preserve-permissions --acls \
      --xattrs --xattrs-include='*' --selinux --sparse \
      --directory=/ "${existing_identity[@]}"
    chmod 0600 "$quarantine/machine-identity.before.tar"
  fi
fi

# Quarantine is complete. Remove only host-key-shaped entries so a fresh key
# algorithm cannot survive alongside the validated restored identity.
shopt -s nullglob
existing_host_keys=("$target_ssh_dir"/ssh_host_*)
if (( ${#existing_host_keys[@]} > 0 )); then
  rm -f -- "${existing_host_keys[@]}"
fi
shopt -u nullglob

install -d "$target_home" "$target_secrets"
cp -a --reflink=auto "$staging/home/tristan/." "$target_home/"
cp -a --reflink=auto "$staging/etc/nixos/secrets/." "$target_secrets/"
chown --reference="$staging/home/tristan" "$target_home"
chmod --reference="$staging/home/tristan" "$target_home"
touch --reference="$staging/home/tristan" "$target_home"
chown --reference="$staging/etc/nixos/secrets" "$target_secrets"
chmod --reference="$staging/etc/nixos/secrets" "$target_secrets"
touch --reference="$staging/etc/nixos/secrets" "$target_secrets"

install -d -m 0700 "$(dirname -- "$target_nm_profile")"
install -d -m 0755 "$target_ssh_dir"
cp -a --reflink=auto "$staged_nm" "$target_nm_profile"
for staged_key in "$staging"/etc/ssh/ssh_host_*; do
  cp -a --reflink=auto "$staged_key" "$target_ssh_dir/"
done

[[ $(stat -c '%u:%g:%a' "$target_nm_profile") == \
   "$expected_identity_uid:$expected_identity_gid:600" ]] || {
  printf 'FAIL: restored NetworkManager profile ownership or mode is unsafe.\n' >&2
  exit 1
}
while IFS=$'\t' read -r key_name expected_fingerprint; do
  restored_public=$target_ssh_dir/$key_name
  restored_private=${restored_public%.pub}
  [[ -f $restored_public && -f $restored_private ]] || {
    printf 'FAIL: restored SSH host-key pair is absent.\n' >&2
    exit 1
  }
  [[ $(stat -c '%u:%g:%a' "$restored_private") == \
     "$expected_identity_uid:$expected_identity_gid:600" && \
     $(stat -c '%u:%g:%a' "$restored_public") == \
     "$expected_identity_uid:$expected_identity_gid:644" ]] || {
    printf 'FAIL: restored SSH host-key ownership or mode is unsafe.\n' >&2
    exit 1
  }
  actual_fingerprint=$(ssh-keygen -lf "$restored_public" -E sha256 | awk '{ print $2 }')
  [[ $actual_fingerprint == "$expected_fingerprint" ]] || {
    printf 'FAIL: restored SSH host-key fingerprint differs from the preinstall record.\n' >&2
    exit 1
  }
done <"$backup_set/ssh-host-key-fingerprints.txt"

mapfile -t expected_ssh_files_sorted < <(printf '%s\n' "${expected_ssh_files[@]}" | sort)
mapfile -t restored_ssh_files < <(
  find "$target_ssh_dir" -maxdepth 1 -mindepth 1 -name 'ssh_host_*' -printf '%f\n' | sort
)
[[ ${#restored_ssh_files[@]} -eq ${#expected_ssh_files_sorted[@]} ]] || {
  printf 'FAIL: restored SSH host-key filename set is not exact.\n' >&2
  exit 1
}
for index in "${!expected_ssh_files_sorted[@]}"; do
  [[ ${restored_ssh_files[index]} == "${expected_ssh_files_sorted[index]}" ]] || {
    printf 'FAIL: restored SSH host-key filename set is not exact.\n' >&2
    exit 1
  }
done

credential=$target_secrets/infernalnexus-smb
credential_result=absent
if [[ -e $credential ]]; then
  expected_uid=0
  expected_gid=0
  [[ $test_mode == 1 ]] && expected_uid=$(id -u) && expected_gid=$(id -g)
  credential_uid=$(stat -c '%u' "$credential")
  credential_gid=$(stat -c '%g' "$credential")
  credential_mode=$(stat -c '%a' "$credential")
  [[ $credential_uid == "$expected_uid" && $credential_gid == "$expected_gid" && \
     $credential_mode == 600 ]] || {
    printf 'FAIL: restored NAS credential metadata is not safely restricted.\n' >&2
    exit 1
  }
  credential_result="verified owner $expected_uid:$expected_gid mode 0600"
fi

restore_timestamp=$(date -u +%Y%m%d-%H%M%S)
report=$report_root/restore-$restore_timestamp.txt
repo_commit=$(git -C "$repo_root" rev-parse HEAD)
rm -rf -- "$staging"
cat >"$report" <<EOF
HELIX CANONICAL RESTORE REPORT
selected_backup_set=$set_name
manifest_sha256=$manifest_checksum
restore_date_utc=$(date --utc --iso-8601=seconds)
restored_scopes=/home/tristan,/etc/nixos/secrets,/etc/NetworkManager/system-connections/towerofdoom.nmconnection,/etc/ssh/ssh_host_*
home_source_paths=$home_entries
home_owner=$archived_home_uid:$archived_home_gid
secrets_source_paths=$secrets_entries
machine_identity_source_files=$identity_entries
ssh_host_key_pairs=$ssh_pair_count
staged_paths=$staged_entries
home_collisions=$home_collisions
secrets_collisions=$secret_collisions
quarantine=$quarantine
archive_validation=passed
staged_tree_validation=passed
credential_metadata=$credential_result
machine_identity_metadata=passed
ssh_fingerprint_verification=passed
restore_repository_commit=$repo_commit
EOF
chmod 0600 "$report"
restore_succeeded=true
trap - EXIT
printf '%s\n' \
  "Restore completed from $set_name." \
  "Restored: $target_home, $target_secrets, the NetworkManager profile, and SSH host-key pairs." \
  "Quarantine: $quarantine" \
  "Report: $report" \
  'Deliberately not restored: hardware configuration, UUIDs, bootloader, Nix store, profiles, generations and inventories.' \
  'Do not rely on remote SSH until after the required reboot.' \
  'Next: reboot so restored SSH and NetworkManager identity is authoritative, then run ./scripts/reinstall-postflight.sh.' \
  'Retain the NAS backup until postflight passes.'
