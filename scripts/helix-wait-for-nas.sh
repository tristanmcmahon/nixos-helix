#!/usr/bin/env bash

set -euo pipefail

# lib/helix.nix prepends nas_host; declaring it here lets the script run
# standalone against any host.
: "${nas_host:?nas_host is not set}"

usage() {
  printf 'Usage: helix-wait-for-nas PORT [SECONDS]\n'
  printf 'Wait until Infernalnexus accepts TCP connections on PORT, for at most\n'
  printf 'SECONDS (default 180). Exits 1 if it never does.\n'
}

case ${1:-} in
--help | -h)
  usage
  exit 0
  ;;
esac
if [[ $# -lt 1 || $# -gt 2 || ! ${1:-} =~ ^[0-9]+$ || ! ${2:-180} =~ ^[0-9]+$ ]]; then
  usage >&2
  exit 2
fi
port=$1
limit=$((10#${2:-180}))

# Each probe is capped at three seconds so an unreachable host cannot hold the
# loop past its deadline for the kernel's full connect timeout.
deadline=$((SECONDS + limit))
until timeout 3 bash -c "exec 3<>/dev/tcp/${nas_host}/${port}" 2>/dev/null; do
  if ((SECONDS >= deadline)); then
    printf 'Infernalnexus (%s) did not accept connections on port %s within %s seconds.\n' \
      "$nas_host" "$port" "$limit" >&2
    exit 1
  fi
  sleep 5
done
