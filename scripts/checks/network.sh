#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

printf 'Checking OpenSSH in the built default system...\n'
[[ -r $system_closure/etc/systemd/system/sshd.service ]]
sshd_test_key=$temporary_directory/ssh_host_ed25519_key
"$system_closure/sw/bin/ssh-keygen" -q -t ed25519 -N '' -f "$sshd_test_key"
sshd_effective=$(
  "$system_closure/sw/bin/sshd" -T \
    -f "$system_closure/etc/ssh/sshd_config" \
    -h "$sshd_test_key" 2>/dev/null | tr '[:upper:]' '[:lower:]'
)
for ssh_setting in \
  'permitrootlogin no' \
  'pubkeyauthentication yes' \
  'passwordauthentication no' \
  'kbdinteractiveauthentication no'; do
  grep -qxF "$ssh_setting" <<<"$sshd_effective"
done

printf 'Checking static native Infernalnexus units...\n'
nas_mount_unit=$system_closure/etc/systemd/system/mnt-infernalnexus-nas1.mount
nas_automount_unit=$system_closure/etc/systemd/system/mnt-infernalnexus-nas1.automount
[[ -r $nas_mount_unit ]]
[[ -r $nas_automount_unit ]]
[[ -L $system_closure/etc/systemd/system/multi-user.target.wants/mnt-infernalnexus-nas1.automount ]]
grep -qF 'What=//192.168.1.8/nas1' "$nas_mount_unit"
grep -qF 'Where=/mnt/infernalnexus/nas1' "$nas_mount_unit"
grep -qF 'Type=cifs' "$nas_mount_unit"
grep -qF 'Options=' "$nas_mount_unit"
grep -qF 'TimeoutSec=15s' "$nas_mount_unit"
grep -qF 'TimeoutIdleSec=10min' "$nas_automount_unit"
if grep -Eq '//192\.168\.1\.8/nas1|/mnt/infernalnexus/nas1|x-systemd\.automount' \
  "$system_closure/etc/fstab"; then
  printf 'Infernalnexus still appears in generated fstab.\n' >&2
  exit 1
fi
"$system_closure/sw/bin/systemd-analyze" verify "$nas_mount_unit" "$nas_automount_unit"

