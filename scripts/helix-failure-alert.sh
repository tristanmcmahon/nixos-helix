#!/usr/bin/env bash

set -euo pipefail

# services/failure-alerts.nix prepends these; declaring them here keeps any
# prepended values and lets the script run standalone.
declare helix_user
declare -a watched_units watched_user_units

usage() {
  printf 'Usage: helix-failure-alert UNIT | --pending\n'
  printf 'Raise a desktop notification for a failed unit, or, with --pending,\n'
  printf 'for every watched unit that is currently failed.\n'
}

# Deliver one notification. Run as root (a system unit failed), it goes to
# helix_user's session bus. A missing session or notification server (logged
# out, SSH only, a desktop still starting) is not an error: the unit stays
# failed, and the login check (--pending) reports it from the next desktop.
notify() {
  local title=$1 body=$2 uid bus attempt
  local -a as_user=()
  if ((EUID == 0)); then
    uid=$(id -u "$helix_user")
    bus=/run/user/$uid/bus
    if [[ ! -S $bus ]]; then
      printf '%s: no session for %s; reported at next login.\n' "$title" "$helix_user"
      return 0
    fi
    as_user=(runuser -u "$helix_user" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=$bus")
  fi
  # Send only to a notification server that is already running. Calling it
  # unowned would D-Bus-activate whichever daemon claims the name, and mako
  # (installed for Hyprland) would then displace Plasma's own for the whole
  # session. At login the desktop's server can register a few seconds after
  # the session target, so wait briefly for it.
  for attempt in 1 2 3 4 5 6; do
    if [[ $("${as_user[@]}" busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
      org.freedesktop.DBus NameHasOwner s org.freedesktop.Notifications 2>/dev/null) == 'b true' ]]; then
      "${as_user[@]}" notify-send --app-name=Helix --urgency=critical --icon=dialog-error \
        -- "$title" "$body" && return 0
    fi
    ((attempt < 6)) && sleep 5
  done
  printf '%s: no notification server answered; reported at next login.\n' "$title"
}

# Name the failed unit, quote the end of its own output (not systemd's
# generic "Failed with result" lines) and say where to look.
report() {
  local scope=$1 unit=$2 lines inspect
  if [[ $scope == user ]]; then
    lines=$(journalctl --user "_SYSTEMD_USER_UNIT=$unit" --lines=3 --output=cat --no-pager 2>/dev/null || true)
    inspect="journalctl --user -u $unit"
  else
    lines=$(journalctl "_SYSTEMD_UNIT=$unit" --lines=3 --output=cat --no-pager 2>/dev/null || true)
    inspect="journalctl -u $unit"
  fi
  notify "$unit failed" "${lines:-No log lines are readable here.}"$'\n'"Details: $inspect"
}

pending() {
  local unit
  for unit in "${watched_units[@]}"; do
    if systemctl is-failed --quiet "$unit"; then
      report system "$unit"
    fi
  done
  for unit in "${watched_user_units[@]}"; do
    if systemctl --user is-failed --quiet "$unit"; then
      report user "$unit"
    fi
  done
}

case ${1:-} in
--help | -h)
  usage
  ;;
--pending)
  [[ $# -eq 1 ]] || {
    usage >&2
    exit 2
  }
  pending
  ;;
'' | -*)
  usage >&2
  exit 2
  ;;
*)
  [[ $# -eq 1 ]] || {
    usage >&2
    exit 2
  }
  if ((EUID == 0)); then
    report system "$1"
  else
    report user "$1"
  fi
  ;;
esac
