#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d --tmpdir=/tmp)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/source" "$work/output"
cat > "$work/bin/age" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -R && -r ${2:-} && ${3:-} == -o && -n ${4:-} ]]
cat >"$4"
MOCK
chmod +x "$work/bin/age"
export PATH="$work/bin:$PATH"
export HELIX_SEAL_TEST_MODE=1
export HELIX_SEAL_TEST_BACKUP_ROOT="$work/source"

set_name=helix-reinstall-20261121-000000
set_dir="$work/source/$set_name"
mkdir -p "$set_dir"
echo 'synthetic root-only data' >"$work/private"
for archive in home-tristan.tar etc-nixos-secrets.tar machine-identity.tar; do
  tar -cf "$set_dir/$archive" -C "$work" private
done
printf 'fixture\n' > "$set_dir/BACKUP-README.txt"
printf 'ssh-ed25519 SHA256:synthetic\n' > "$set_dir/ssh-host-key-fingerprints.txt"
(
  cd "$set_dir"
  sha256sum BACKUP-README.txt home-tristan.tar etc-nixos-secrets.tar \
    machine-identity.tar ssh-host-key-fingerprints.txt > SHA256SUMS
  : > COMPLETE
)
printf 'age1examplepubkeyfortest\n' > "$work/recipients.txt"
sealer="$repo_root/scripts/helix-reinstall-seal.sh"
bash "$sealer" "$set_name" --recipients-file "$work/recipients.txt" --output-dir "$work/output" >"$work/out"
sealed="$work/output/$set_name.sealed"
[[ -d $sealed ]]
[[ -f $sealed/$set_name.tar.age ]]
( cd "$sealed" && sha256sum --check --strict "$set_name.tar.age.sha256" >/dev/null )
tar -tf "$sealed/$set_name.tar.age" | grep -qF "$set_name/home-tristan.tar"
grep -qF '"format": "helix-reinstall-seal-v1"' "$sealed/$set_name.sealed-manifest.json"
[[ -f "$set_dir/COMPLETE" ]]
if bash "$sealer" "$set_name" --recipients-file "$work/recipients.txt" --output-dir "$work/output" >/dev/null 2>&1; then
  echo 'Sealer overwrote existing output' >&2
  exit 1
fi
mkdir "$work/invalid-output"
printf 'tampered\n' >>"$set_dir/home-tristan.tar"
if bash "$sealer" "$set_name" --recipients-file "$work/recipients.txt" --output-dir "$work/invalid-output" >/dev/null 2>&1; then
  echo 'Sealer accepted a changed archive' >&2
  exit 1
fi
[[ -z $(find "$work/invalid-output" -mindepth 1 -print -quit) ]]
echo 'Canonical reinstall sealing tests passed (age mocked; live decryption is still required).'
