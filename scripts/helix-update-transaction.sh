#!/usr/bin/env bash
# Sourced by helix-update. All arguments are explicit to permit isolated
# failure-injection tests; only the caller chooses the privileged GC root.

helix_transaction_exit() {
  local code=$1
  trap - EXIT INT TERM
  if ((code != 0 && HELIX_PROMOTION_STARTED)); then
    printf 'Candidate promotion interrupted or failed; restoring prior boot and runtime...\n' >&2
    if ! sudo nix-env --profile /nix/var/nix/profiles/system --set "$HELIX_PREVIOUS_PROFILE"; then
      printf 'CRITICAL: failed to restore old system profile; use the boot menu.\n' >&2
    fi
    if ! sudo "$HELIX_PREVIOUS_RUNNING/bin/switch-to-configuration" switch; then
      printf 'CRITICAL: failed to restore running configuration; use the boot menu.\n' >&2
    fi
  fi
  exit "$code"
}

helix_guarded_promote() {
  if (($# != 4)); then
    printf 'Usage: helix_guarded_promote CANDIDATE PREVIOUS_RUNNING PREVIOUS_PROFILE GC_ROOT\n' >&2
    return 2
  fi

  local candidate=$1 previous=$2 profile=$3 gc_root=$4 gc_directory gc_tmp
  gc_directory=$(dirname -- "$gc_root")
  gc_tmp="$gc_directory/.helix-fallback-$$"
  # Create or replace the GC root atomically *before* the first test-activate.
  # The root only changes on attended promotion, never on an unattended timer.
  sudo install -d -m 0755 "$gc_directory"
  sudo ln -s -- "$previous" "$gc_tmp"
  if ! sudo mv -Tf -- "$gc_tmp" "$gc_root"; then
    sudo rm -f -- "$gc_tmp" || true
    printf 'Failed to protect known-good system store path: %s\n' "$gc_root" >&2
    return 1
  fi

  HELIX_PREVIOUS_RUNNING=$previous
  HELIX_PREVIOUS_PROFILE=$profile
  HELIX_PROMOTION_STARTED=1
  trap 'helix_transaction_exit $?' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  printf 'Test-activating candidate...\n'
  sudo "$candidate/bin/switch-to-configuration" test

  printf 'Running candidate runtime health gate...\n'
  "$candidate/sw/bin/helix-health" --check

  printf 'Candidate health gate passed; registering generation...\n'
  sudo nix-env --profile /nix/var/nix/profiles/system --set "$candidate"
  printf 'Selecting registered generation for boot...\n'
  sudo "$candidate/bin/switch-to-configuration" switch

  HELIX_PROMOTION_STARTED=0
  trap - EXIT INT TERM
  printf 'Protected known-good fallback: %s -> %s\n' "$gc_root" "$previous"
}
