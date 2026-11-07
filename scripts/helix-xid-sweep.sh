#!/usr/bin/env bash

set -euo pipefail

# Hunt an intermittent GPU hang by repetition: launch one Steam game again and
# again, changing exactly one environment variable per variant, and record
# whether the kernel logs an NVIDIA Xid. It starts and stops Steam itself, in a
# transient systemd scope per run, so the launch environment is the only thing
# that differs between variants. The Proton build is whatever Steam has
# selected; it is recorded, never changed, and no Steam state is edited.
# docs/xid109.md describes the hang this was written for.

usage() {
  cat <<'EOF'
Usage: helix-xid-sweep [-n MINUTES] [-r ROUNDS] [-a APPID] [-s RUN] [NAME:VAR=VALUE ...]

Launch APPID (default 4078430, Galactic Racer) through Steam once per variant
per round. A run ends at the first Xid or after MINUTES (default 12, launch
included). Each variant sets at most one environment variable; "NAME:" alone
is the baseline. Variants rotate for ROUNDS rounds (default 3), so the baseline
is interleaved with the others. -s RUN resumes at that run number.

Defaults: baseline:  heap:PROTON_VKD3D_HEAP=1  hvv:VKD3D_CONFIG=no_upload_hvv

Quit Steam first, and select the Proton build to test in Steam. Play while it
runs. Results go to ~/.local/state/helix/xid/: results.tsv and, per run, the
telemetry, kernel log lines and a snapshot taken at the hang.
EOF
}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

minutes=12
rounds=3
appid=4078430
first_run=1
while getopts ':n:r:a:s:h' option; do
  case $option in
  n) minutes=$OPTARG ;;
  r) rounds=$OPTARG ;;
  a) appid=$OPTARG ;;
  s) first_run=$OPTARG ;;
  h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
done
shift $((OPTIND - 1))
for number in "$minutes" "$rounds" "$appid" "$first_run"; do
  if [[ ! $number =~ ^[0-9]+$ || $number -eq 0 ]]; then
    usage >&2
    exit 2
  fi
done

if (($# == 0)); then
  set -- baseline: heap:PROTON_VKD3D_HEAP=1 hvv:VKD3D_CONFIG=no_upload_hvv
fi
names=()
assigns=()
baseline=''
for variant in "$@"; do
  name=${variant%%:*}
  assign=${variant#*:}
  if [[ $variant != *:* || ! $name =~ ^[A-Za-z0-9._-]+$ ]] ||
    [[ -n $assign && ! $assign =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*$ ]]; then
    printf 'Bad variant %q: use NAME: or NAME:VAR=VALUE, one variable only.\n' "$variant" >&2
    exit 2
  fi
  names+=("$name")
  assigns+=("$assign")
  if [[ -z $assign && -z $baseline ]]; then
    baseline=$name
  fi
done
if [[ -z $baseline ]]; then
  printf 'Warning: no baseline variant (NAME:), so nothing can be compared.\n' >&2
fi

for tool in nvidia-smi journalctl systemd-run systemctl steam pgrep; do
  command -v "$tool" >/dev/null || die "Missing command: $tool"
done
if pgrep -x steam >/dev/null; then
  die 'Steam is running. Quit it first: a running Steam would ignore the variant environment.'
fi
timeout 15 nvidia-smi -L >/dev/null 2>&1 || die 'The GPU is not answering. Reboot first.'

state=${XDG_STATE_HOME:-$HOME/.local/state}/helix/xid
cgroup_root=${CGROUP_ROOT:-/sys/fs/cgroup}
cooldown=${COOLDOWN:-15}
# The hang showed as 100% utilisation at 48-60 W (genuine load draws 200 W+).
wedge_watts=${WEDGE_WATTS:-100}
wedge_samples=${WEDGE_SAMPLES:-3}
sweep=$(date +%Y%m%d-%H%M%S)
mkdir -p "$state/$sweep"
driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n 1)
kernel=$(uname -r)
bug_report=$(dirname "$(readlink -f "$(command -v nvidia-smi)")")/nvidia-bug-report.sh
bug_report_done=0
total=$((${#names[@]} * rounds))
limit=$((minutes * 60))
smi_pid=''
klog_pid=''
current_scope=''

can_sudo=0
if sudo -v; then
  can_sudo=1
else
  printf 'No sudo: the nvidia-bug-report capture will be skipped.\n'
fi

# PIDs inside a run's scope: exactly the processes Steam started for it.
scope_pids() {
  local group
  group=$(systemctl --user show -p ControlGroup --value "$1" 2>/dev/null || true)
  [[ -z $group ]] || cat "$cgroup_root$group/cgroup.procs" 2>/dev/null || true
}

# The Proton build in use, from the launch command line.
proton_of() {
  local pid
  for pid in $(scope_pids "$1"); do
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -oE '[^ ]*/proton ' | head -n 1 || true
  done | head -n 1 | tr -d ' '
}

# Did the variable reach the game? Proton can rewrite its environment, so this
# checks that the game's own process holds it: a silent no-op is not a result.
# Prints ok, MISSING, or waiting (no game process yet).
verify_env() {
  local scope=$1 assign=$2 pid seen=0
  for pid in $(scope_pids "$scope"); do
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q '[.]exe' || continue
    seen=1
    if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null |
      grep -F -- "${assign%%=*}=" | grep -qF -- "${assign#*=}"; then
      printf 'ok\n'
      return 0
    fi
  done
  if ((seen)); then printf 'MISSING\n'; else printf 'waiting\n'; fi
}

snapshot() {
  local file=$1 scope=$2 pid
  {
    date -Is
    printf 'kernel %s  driver %s\n' "$kernel" "$driver"
    timeout 10 nvidia-smi --query-gpu=name,pstate,pcie.link.gen.current,pcie.link.width.current \
      --format=csv 2>&1 || printf 'nvidia-smi gave no answer (the GPU is likely wedged)\n'
    printf '\n--- processes in the run scope\n'
    for pid in $(scope_pids "$scope"); do
      ps -o pid=,etimes=,args= -p "$pid" 2>/dev/null | cut -c1-220 || true
    done
    printf '\n--- launch environment of its Windows processes\n'
    for pid in $(scope_pids "$scope"); do
      tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q '[.]exe' || continue
      tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null |
        grep -E '^(VKD3D|PROTON|DXVK|WINE|STEAM_COMPAT)[A-Z_0-9]*=' || true
    done | sort -u
  } >"$file" 2>&1
}

record() { # run name assign outcome seconds env proton
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$sweep" "$1" "$2" "$3" "$4" "$5" "$6" "${7:--}" "$driver" "$kernel" \
    >>"$state/results.tsv"
}

gpu_state=ok

do_run() {
  local run=$1 name=$2 assign=$3
  local scope="helix-xid-$sweep-$run" dir fifo klog_fd launcher
  local line outcome='' started=$SECONDS now last_check=-1 last_status=$SECONDS
  local env_state=n/a proton='' sample prev_sample='' low_samples=0 wedge_warned=0
  local util='' power='' clock='' temp='' elapsed
  dir=$state/$sweep/$(printf '%02d' "$run")-$name
  fifo=$dir/kernel.fifo
  mkdir -p "$dir"
  mkfifo "$fifo"
  [[ -z $assign ]] || env_state=unchecked

  printf '\n=== Run %s of %s: %s%s ===\n' "$run" "$total" "$name" "${assign:+  ($assign)}"
  printf 'Steam starts now. Play; this run ends at an Xid or after %s minutes.\n' "$minutes"

  nvidia-smi --query-gpu=timestamp,utilization.gpu,power.draw,clocks.sm,temperature.gpu \
    --format=csv,noheader,nounits -l 1 >"$dir/telemetry.csv" 2>&1 &
  smi_pid=$!
  journalctl -k -f --since now --no-pager -o short-iso >"$fifo" 2>&1 &
  klog_pid=$!
  exec {klog_fd}<"$fifo"

  local -a setenv=()
  [[ -z $assign ]] || setenv=(-E "$assign")
  current_scope=$scope.scope
  systemd-run --user --scope --quiet --collect --unit="$scope" -p TimeoutStopSec=20 \
    "${setenv[@]}" -- steam -applaunch "$appid" >"$dir/steam.log" 2>&1 &
  launcher=$!

  while ((SECONDS - started < limit)); do
    if read -r -t 1 -u "$klog_fd" line; then
      if [[ $line =~ Xid\ \(PCI:[^\)]*\):\ ([0-9]+) ]]; then
        outcome=FAIL-${BASH_REMATCH[1]}
        printf '%s\n' "$line" >"$dir/xid-line.txt"
        break
      fi
    fi
    if ! kill -0 "$klog_pid" 2>/dev/null; then
      outcome=ERROR
      printf 'The kernel log reader died.\n' >&2
      break
    fi
    now=$SECONDS
    ((now != last_check)) || continue
    last_check=$now
    if ((now - started > 25)) && ! systemctl --user is-active --quiet "$current_scope"; then
      outcome=ERROR
      printf 'Steam exited early; see %s/steam.log\n' "$dir" >&2
      break
    fi

    # Precursor seen before the first captured hang: pegged utilisation at
    # far-too-low power. Informational only.
    sample=$(tail -n 1 "$dir/telemetry.csv" 2>/dev/null || true)
    if [[ $sample != "$prev_sample" ]]; then
      prev_sample=$sample
      IFS=, read -r _ util power clock temp <<<"$sample" || true
      util=${util// /} power=${power// /} clock=${clock// /} temp=${temp// /}
      if [[ $util =~ ^[0-9]+$ && $power =~ ^[0-9]+ ]] && ((util >= 95 && ${power%%.*} < wedge_watts)); then
        low_samples=$((low_samples + 1))
        if ((low_samples >= wedge_samples && wedge_warned == 0)); then
          wedge_warned=1
          printf '\a[%3ss] WEDGE SIGNATURE: %s%% utilisation at %s W\n' \
            "$((now - started))" "$util" "$power"
        fi
      else
        low_samples=0
      fi
    fi

    if ((now - started >= 75)); then
      [[ -n $proton ]] || proton=$(proton_of "$current_scope")
      if [[ $env_state == unchecked ]]; then
        env_state=$(verify_env "$current_scope" "$assign")
        case $env_state in
        waiting) env_state=unchecked ;;
        MISSING) printf '\a[%3ss] WARNING: %s is not in the game'\''s environment; this run does not test it.\n' "$((now - started))" "${assign%%=*}" ;;
        ok) printf '[%3ss] %s reached the game.\n' "$((now - started))" "${assign%%=*}" ;;
        *) ;;
        esac
      fi
    fi

    if ((now - last_status >= 15)); then
      last_status=$now
      printf '[%3ss] util=%s%% power=%sW clock=%sMHz temp=%sC\n' \
        "$((now - started))" "${util:-?}" "${power:-?}" "${clock:-?}" "${temp:-?}"
    fi
  done
  [[ -n $outcome ]] || outcome=PASS
  elapsed=$((SECONDS - started))
  [[ $env_state != unchecked ]] || env_state=unverified
  [[ -n $proton ]] || proton=$(proton_of "$current_scope")

  if [[ $outcome == FAIL-* ]]; then
    printf '\a\n*** %s after %ss: capturing evidence ***\n' "$outcome" "$elapsed"
    snapshot "$dir/at-xid.txt" "$current_scope"
    sleep 5
    if ((bug_report_done == 0 && can_sudo)) && [[ -x $bug_report ]]; then
      printf 'Collecting nvidia-bug-report (about a minute)...\n'
      # The tool needs root; its console output is deliberately logged as the
      # invoking user, and the report is handed back to that user afterwards.
      # shellcheck disable=SC2024
      if sudo -n timeout 300 "$bug_report" --output-file "$dir/nvidia-bug-report.log.gz" \
        >"$dir/bug-report.out" 2>&1; then
        sudo -n chown "$(id -u):$(id -g)" "$dir/nvidia-bug-report.log.gz" || true
      else
        printf 'nvidia-bug-report failed; see %s/bug-report.out\n' "$dir"
      fi
      bug_report_done=1
    fi
  fi

  systemctl --user stop "$current_scope" 2>/dev/null || true
  wait "$launcher" 2>/dev/null || true
  kill "$smi_pid" "$klog_pid" 2>/dev/null || true
  wait "$smi_pid" "$klog_pid" 2>/dev/null || true
  exec {klog_fd}<&-
  rm -f "$fifo"
  smi_pid='' klog_pid='' current_scope=''
  for _ in $(seq 30); do
    pgrep -x steam >/dev/null || break
    sleep 1
  done
  if pgrep -x steam >/dev/null; then
    gpu_state=steam
  elif [[ $outcome == FAIL-* ]] && ! timeout 15 nvidia-smi -L >/dev/null 2>&1; then
    gpu_state=wedged
  fi

  record "$run" "$name" "$assign" "$outcome" "$elapsed" "$env_state" "$proton"
  printf 'Run %s: %s after %ss (variable reached the game: %s)\n' "$run" "$outcome" "$elapsed" "$env_state"
}

summary() {
  [[ -s $state/results.tsv ]] || return 0
  awk -F'\t' -v sweep="$sweep" -v base="$baseline" '
    $1 == sweep {
      v = $3
      if (!(v in runs)) order[++count] = v
      runs[v]++
      if ($7 == "MISSING") invalid[v]++
      else if ($5 ~ /^FAIL/) { fail[v]++; times[v] = times[v] " " $6 "s" }
      else if ($5 == "PASS") pass[v]++
    }
    END {
      if (!count) exit
      printf "\nSweep %s\n", sweep
      for (i = 1; i <= count; i++) {
        v = order[i]
        printf "%-12s runs %d  pass %d  fail %d  invalid %d  time to fail:%s\n", \
          v, runs[v], pass[v], fail[v], invalid[v], (times[v] == "" ? " -" : times[v])
      }
      if (base == "") exit
      if (!fail[base]) {
        print "\nThe baseline never failed, so no variant can be judged. Run more rounds."
        exit
      }
      for (i = 1; i <= count; i++) {
        v = order[i]
        if (v != base) printf "%s: %d of %d runs failed, against the baseline'\''s %d of %d.\n", \
          v, fail[v], runs[v], fail[base], runs[base]
      }
    }' "$state/results.tsv"
  printf 'Full detail: %s/%s/\n' "$state" "$sweep"
}

finish() {
  [[ -z $smi_pid ]] || kill "$smi_pid" 2>/dev/null || true
  [[ -z $klog_pid ]] || kill "$klog_pid" 2>/dev/null || true
  [[ -z $current_scope ]] || systemctl --user stop "$current_scope" 2>/dev/null || true
  summary
}
trap finish EXIT
trap 'printf "\nInterrupted.\n"; exit 130' INT TERM

printf 'Driver %s, kernel %s. %s runs of up to %s minutes each.\n' "$driver" "$kernel" "$total" "$minutes"
for ((run = first_run; run <= total; run++)); do
  index=$(((run - 1) % ${#names[@]}))
  do_run "$run" "${names[index]}" "${assigns[index]}"
  case $gpu_state in
  steam) die 'Steam did not exit. Quit it by hand, then resume with -s '"$((run + 1))"'.' ;;
  wedged) die "The GPU stopped answering after the hang. Reboot, then resume with -s $((run + 1))." ;;
  *) ;;
  esac
  if ((run < total)); then sleep "$cooldown"; fi
done
