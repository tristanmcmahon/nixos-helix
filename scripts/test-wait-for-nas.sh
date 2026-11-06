#!/usr/bin/env bash

set -euo pipefail

# Behavioural test for helix-wait-for-nas against a local listener: it must
# return at once when the port answers, give up with status 1 when it never
# does, and refuse bad arguments with status 2.
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script=$repo_root/scripts/helix-wait-for-nas.sh
export nas_host=127.0.0.1

port_file=$(mktemp)
trap 'kill "${listener:-0}" 2>/dev/null || true; rm -f -- "$port_file"' EXIT
python3 -I -c '
import socket, sys, time
server = socket.socket()
server.bind(("127.0.0.1", 0))
server.listen(5)
open(sys.argv[1], "w").write(str(server.getsockname()[1]))
time.sleep(60)
' "$port_file" &
listener=$!
until [[ -s $port_file ]]; do sleep 0.1; done
open_port=$(<"$port_file")

status() {
  local code=0
  "$script" "$@" >/dev/null 2>&1 || code=$?
  printf '%s' "$code"
}

[[ $(status "$open_port" 5) == 0 ]]
# Port 1 is never open on loopback.
[[ $(status 1 0) == 1 ]]
# A leading-zero limit is decimal: 08 must still be waiting when timeout stops
# it, not dead at once on an octal parse error.
[[ $(timeout 3 "$script" 1 08 >/dev/null 2>&1; printf '%s' "$?") == 124 ]]
[[ $(status abc) == 2 ]]
[[ $(status "$open_port" 5 extra) == 2 ]]
[[ $(status) == 2 ]]
[[ $(status --help) == 0 ]]
printf 'helix-wait-for-nas behaves.\n'
