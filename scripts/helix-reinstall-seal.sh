#!/usr/bin/env bash
# Seal a verified canonical reinstall set; never mutate the source NAS.
set -euo pipefail
usage() {
  printf 'Usage: helix-reinstall-seal BACKUP_SET --recipients-file PUBLIC_KEYS --output-dir OFF_NAS_DIRECTORY\n'
}

[[ $# -eq 5 && ${2:-} == --recipients-file && ${4:-} == --output-dir ]] || {
  usage >&2
  exit 2
}
set_name=$1
recipients=$3
output_dir=$5
[[ $set_name =~ ^helix-reinstall-[0-9]{8}-[0-9]{6}$ ]] || {
  printf 'Refusing a non-canonical backup set name.\n' >&2
  exit 2
}
[[ -f $recipients && ! -L $recipients && -r $recipients ]] || {
  printf 'Refusing absent/unreadable/linked age recipient file.\n' >&2
  exit 1
}
if grep -Eq 'AGE-SECRET-KEY-|BEGIN (OPENSSH|RSA|EC) PRIVATE KEY' "$recipients"; then
  printf 'Recipient file contains private key material; use age PUBLIC recipient keys.\n' >&2
  exit 1
fi
[[ -d $output_dir && ! -L $output_dir ]] || {
  printf 'Output directory must exist and may not be a symlink.\n' >&2
  exit 1
}
for command in age tar sha256sum realpath findmnt python3; do
  command -v "$command" >/dev/null || {
    printf 'Required command missing: %s\n' "$command" >&2
    exit 1
  }
done

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${HELIX_SEAL_TEST_MODE:-0} == 1 ]]; then
  source_root=${HELIX_SEAL_TEST_BACKUP_ROOT:-}
  [[ $source_root == /tmp/* && -d $source_root ]] || exit 1
else
  ((EUID == 0)) || {
    printf 'Run with sudo to read protected NAS recovery files.\n' >&2
    exit 1
  }
  # shellcheck source=scripts/reinstall/facts.sh
  source "$repo_root/scripts/reinstall/facts.sh"
  source_root=$helix_backup_root
  nas_mount=$helix_nas_mount
  stat -- "$nas_mount" >/dev/null
  mountpoint -q "$nas_mount" || {
    printf 'Refusing unmounted NAS source.\n' >&2
    exit 1
  }
  mapfile -t sources < <(findmnt -rn --target "$nas_mount" --types cifs -o SOURCE)
  [[ ${#sources[@]} -eq 1 && ${sources[0]%/} == "$helix_nas_source" ]] || {
    printf 'Refusing unexpected CIFS backup source.\n' >&2
    exit 1
  }
  output_real=$(realpath -e -- "$output_dir")
  nas_real=$(realpath -e -- "$nas_mount")
  [[ $output_real != "$nas_real" && $output_real != "$nas_real"/* ]] || {
    printf 'Output must not be on Infernalnexus.\n' >&2
    exit 1
  }
  source_device=$(findmnt -nro MAJ:MIN --target "$nas_mount")
  output_device=$(findmnt -nro MAJ:MIN --target "$output_dir")
  [[ -n $output_device && $output_device != "$source_device" ]] || {
    printf 'Output must use a separate filesystem from the NAS source.\n' >&2
    exit 1
  }
fi

source_set=$source_root/$set_name
[[ -d $source_set && ! -L $source_set ]] || {
  printf 'Canonical backup set missing or linked.\n' >&2
  exit 1
}
for name in COMPLETE SHA256SUMS BACKUP-README.txt home-tristan.tar etc-nixos-secrets.tar machine-identity.tar ssh-host-key-fingerprints.txt; do
  [[ -f $source_set/$name && ! -L $source_set/$name ]] || {
    printf 'Missing or linked canonical artifact: %s\n' "$name" >&2
    exit 1
  }
done
if find "$source_set" -type l -print -quit | grep -q .; then
  printf 'Refusing source set containing symlinks.\n' >&2
  exit 1
fi
(cd "$source_set" && sha256sum --check --strict SHA256SUMS >/dev/null)
for archive in home-tristan.tar etc-nixos-secrets.tar machine-identity.tar; do
  tar -tf "$source_set/$archive" >/dev/null
done

destination=$output_dir/$set_name.sealed
[[ ! -e $destination && ! -L $destination ]] || {
  printf 'Refusing to overwrite existing seal: %s\n' "$destination" >&2
  exit 1
}
umask 077
stage=$(mktemp -d "$output_dir/.$set_name.seal.INCOMPLETE.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
cipher=$stage/$set_name.tar.age
# tar streams unencrypted bytes *directly* into age; no plaintext local copy
# and no writes to the original NAS archive.
tar -C "$source_root" -cf - "$set_name" | age -R "$recipients" -o "$cipher"
sha256sum "$cipher" | sed "s|$stage/||" >"$stage/$set_name.tar.age.sha256"
source_manifest=$(sha256sum "$source_set/SHA256SUMS" | awk '{ print $1 }')
sealed_sha=$(sha256sum "$cipher" | awk '{ print $1 }')
python3 - "$stage/$set_name.sealed-manifest.json" "$set_name" "$source_manifest" "$sealed_sha" <<'PY'
import json, sys
path, name, source_sha, sealed_sha = sys.argv[1:]
with open(path, "w", encoding="utf-8") as out:
    json.dump({
        "format": "helix-reinstall-seal-v1",
        "source_set": name,
        "source_manifest_sha256": source_sha,
        "sealed_archive": name + ".tar.age",
        "sealed_sha256": sealed_sha,
        "encryption": "age-recipients-v1"
    }, out, indent=2)
    out.write("\n")
PY
mv -T --no-clobber -- "$stage" "$destination"
[[ -d $destination && ! -e $stage ]] || {
  printf 'Could not atomically publish the sealed directory.\n' >&2
  exit 1
}
trap - EXIT
printf 'Sealed canonical recovery set: %s\n' "$destination"
printf 'Still required: off-NAS transport and real age decrypt + restore drill.\n'
