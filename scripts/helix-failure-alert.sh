#!/usr/bin/env bash

set -euo pipefail

# services/failure-alerts.nix prepends these; declaring them here keeps any
# prepended values and lets the script run standalone, where a sudo run
# notifies the user who invoked it.
: "${helix_user:=${SUDO_USER:-$(id -un)}}"
declare -a watched_units watched_user_units

# Set once a wait for a notification server has timed out, so a login with
# several failed units waits once, not once per unit.
no_server=0

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
  if ((no_server)); then
    printf '%s: no notification server answered; reported at next login.\n' "$title"
    return 0
  fi
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
  no_server=1
  printf '%s: no notification server answered; reported at next login.\n' "$title"
}

# Name the failed unit and systemd's verdict (exit-code, timeout, oom-kill),
# quote the end of that run's own output and say where to look. OnFailure
# passes the failed run's identity as MONITOR_*; the login check asks systemd,
# which keeps it while the unit stays failed.
report() {
  local scope=$1 unit=$2 invocation result lines='' body
  local -a scoped=()
  [[ $scope == user ]] && scoped=(--user)
  invocation=${MONITOR_INVOCATION_ID:-$(systemctl "${scoped[@]}" show --property=InvocationID --value "$unit" 2>/dev/null || true)}
  result=${MONITOR_SERVICE_RESULT:-$(systemctl "${scoped[@]}" show --property=Result --value "$unit" 2>/dev/null || true)}
  if [[ -n $invocation ]]; then
    lines=$(journalctl "${scoped[@]}" "_SYSTEMD_INVOCATION_ID=$invocation" --lines=3 \
      --output=cat --no-pager 2>/dev/null || true)
  fi
  # Not every journal records the invocation for user units: fall back to the
  # unit's own most recent output.
  if [[ -z $lines ]]; then
    if [[ $scope == user ]]; then
      lines=$(journalctl --user "_SYSTEMD_USER_UNIT=$unit" --lines=3 --output=cat --no-pager 2>/dev/null || true)
    else
      lines=$(journalctl "_SYSTEMD_UNIT=$unit" --lines=3 --output=cat --no-pager 2>/dev/null || true)
    fi
  fi
  body=${result:+Result: $result$'\n'}${lines:-No output from the failed run is readable here.}
  notify "$unit failed" "$body"$'\n'"Details: journalctl ${scoped[*]}${scoped:+ }-u $unit"
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
