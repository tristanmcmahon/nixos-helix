# shellcheck shell=bash
# Sourced by the reinstall scripts. Reads Helix's host facts from
# config/helix.nix and config/infernalnexus.nix with one evaluation, so the
# scripts never restate them. Paths inside existing backup archives
# (home/tristan/...) are archive layout, not host facts, and stay literal.
helix_facts_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
helix_facts=$(
  nix-instantiate --eval --raw -E "
    let
      helix = import $helix_facts_root/config/helix.nix;
      nas = import $helix_facts_root/config/infernalnexus.nix;
    in builtins.concatStringsSep \"\n\" [
      \"helix_user=\${helix.user}\"
      \"helix_home=\${helix.home}\"
      \"helix_checkout=\${helix.checkout}\"
      \"helix_games_uuid=\${helix.gamesNvme.uuid}\"
      \"helix_nas_mount=\${nas.shares.nas1.mountPoint}\"
      \"helix_nas_source=\${nas.shares.nas1.source}\"
    ]
  "
) || {
  printf 'FAIL: could not read Helix host facts from %s/config.\n' "$helix_facts_root" >&2
  exit 1
}
while IFS='=' read -r helix_fact_name helix_fact_value; do
  case $helix_fact_name in
  helix_user | helix_home | helix_checkout | helix_games_uuid | helix_nas_mount | helix_nas_source)
    printf -v "$helix_fact_name" '%s' "$helix_fact_value"
    ;;
  *)
    printf 'FAIL: unexpected Helix fact: %s\n' "$helix_fact_name" >&2
    exit 1
    ;;
  esac
done <<<"$helix_facts"
helix_backup_root=$helix_nas_mount/backup
# shellcheck disable=SC2034 # Consumed by the sourcing script.
readonly helix_user helix_home helix_checkout helix_games_uuid helix_nas_mount \
  helix_nas_source helix_backup_root
unset helix_facts helix_fact_name helix_fact_value helix_facts_root
