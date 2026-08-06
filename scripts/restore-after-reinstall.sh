#!/usr/bin/env bash

set -euo pipefail

canonical_repo=/home/tristan/Projects/nixos-helix
nas_mount=/mnt/infernalnexus/nas1
backup_root=/mnt/infernalnexus/nas1/backup
expected_source=//192.168.1.8/nas1
target_home=/home/tristan
target_secrets=/etc/nixos/secrets
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
    HELIX_RESTORE_TEST_STAGING_BASE HELIX_RESTORE_TEST_QUARANTINE_ROOT; do
    value=${!variable:-}
    [[ -n $value && $(realpath -m -- "$value") == "$test_base"/* ]] || {
      printf 'FAIL: invalid internal restore-test path.\n' >&2
      exit 1
    }
  done
  backup_root=$HELIX_RESTORE_TEST_BACKUP_ROOT
  target_home=$HELIX_RESTORE_TEST_HOME
  target_secrets=$HELIX_RESTORE_TEST_SECRETS
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
  "Secrets archive: verified ($secrets_entries paths, approximately $secrets_bytes data bytes)" \
  "Restore target: $target_home ($home_state)" \
  "Secrets target: $target_secrets" \
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
  'Will restore only /home/tristan and /etc/nixos/secrets from staged archives.' \
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
staged_entries=$(python3 "$validator" staged "$staging")

quarantine=none
if (( home_collisions > 0 || secret_collisions > 0 )); then
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
fi

install -d "$target_home" "$target_secrets"
cp -a --reflink=auto "$staging/home/tristan/." "$target_home/"
cp -a --reflink=auto "$staging/etc/nixos/secrets/." "$target_secrets/"
chown --reference="$staging/home/tristan" "$target_home"
chmod --reference="$staging/home/tristan" "$target_home"
touch --reference="$staging/home/tristan" "$target_home"
chown --reference="$staging/etc/nixos/secrets" "$target_secrets"
chmod --reference="$staging/etc/nixos/secrets" "$target_secrets"
touch --reference="$staging/etc/nixos/secrets" "$target_secrets"

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
restored_scopes=/home/tristan,/etc/nixos/secrets
home_source_paths=$home_entries
secrets_source_paths=$secrets_entries
staged_paths=$staged_entries
home_collisions=$home_collisions
secrets_collisions=$secret_collisions
quarantine=$quarantine
archive_validation=passed
staged_tree_validation=passed
credential_metadata=$credential_result
restore_repository_commit=$repo_commit
EOF
chmod 0600 "$report"
restore_succeeded=true
trap - EXIT
printf '%s\n' \
  "Restore completed from $set_name." \
  "Restored: $target_home and $target_secrets." \
  "Quarantine: $quarantine" \
  "Report: $report" \
  'Deliberately not restored: hardware configuration, UUIDs, bootloader, Nix store, profiles, generations and inventories.' \
  'Next: run ./scripts/reinstall-postflight.sh and retain the NAS backup until postflight passes.'
