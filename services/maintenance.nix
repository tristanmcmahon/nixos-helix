{ pkgs, ... }:

let
  cleanup = pkgs.writeShellApplication {
    name = "helix-nix-cleanup";
    runtimeInputs = [
      pkgs.nix
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      profile=/nix/var/nix/profiles/system
      planning=false
      temporary_listing=
      active_generation=

      cleanup_temporary_listing() {
        if [[ -n "$temporary_listing" ]]; then
          rm -f -- "$temporary_listing"
        fi
      }
      trap cleanup_temporary_listing EXIT

      case $# in
        0)
          temporary_listing=$(mktemp)
          nix-env --profile "$profile" --list-generations > "$temporary_listing"
          listing=$temporary_listing
          ;;
        3)
          if [[ $1 != --plan ]]; then
            printf 'Usage: helix-nix-cleanup [--plan GENERATION_LISTING ACTIVE_GENERATION]\n' >&2
            exit 2
          fi
          planning=true
          listing=$2
          active_generation=$3
          ;;
        *)
          printf 'Usage: helix-nix-cleanup [--plan GENERATION_LISTING ACTIVE_GENERATION]\n' >&2
          exit 2
          ;;
      esac

      mapfile -t selected_generations < <(
        awk '$1 ~ /^[0-9]+$/ && $NF == "(current)" { print $1 }' "$listing"
      )
      if [[ ''${#selected_generations[@]} -eq 1 ]]; then
        printf 'Profile-selected generation: %s\n' "''${selected_generations[0]}"
      else
        printf 'Profile-selected generation: unknown (%s markers)\n' \
          "''${#selected_generations[@]}"
      fi

      if [[ $planning == true ]]; then
        mapfile -t generations < <(
          awk '$1 ~ /^[0-9]+$/ { print $1 }' "$listing" | sort -nru
        )
        active_matches=0
        for generation in "''${generations[@]}"; do
          if [[ $generation == "$active_generation" ]]; then
            ((active_matches += 1))
          fi
        done
      else
        if ! active_system=$(readlink -f /run/current-system); then
          printf 'Refusing cleanup: /run/current-system could not be resolved.\n' >&2
          exit 1
        fi
        generations=()
        active_matches=0

        shopt -s nullglob
        for generation_link in /nix/var/nix/profiles/system-*-link; do
          generation=''${generation_link##*/system-}
          generation=''${generation%-link}
          if [[ ! $generation =~ ^[0-9]+$ ]]; then
            continue
          fi

          generations+=("$generation")
          if generation_system=$(readlink -f -- "$generation_link") && \
            [[ $generation_system == "$active_system" ]]; then
            active_generation=$generation
            ((active_matches += 1))
          fi
        done
        mapfile -t generations < <(printf '%s\n' "''${generations[@]}" | sort -nru)
      fi

      if [[ $active_matches -ne 1 ]]; then
        printf 'Refusing cleanup: expected exactly one generation matching the active system, found %s.\n' \
          "$active_matches" >&2
        exit 1
      fi

      retained=("$active_generation")
      deleted=()
      retained_others=0
      for generation in "''${generations[@]}"; do
        if [[ $generation == "$active_generation" ]]; then
          continue
        fi
        if [[ $retained_others -lt 2 ]]; then
          retained+=("$generation")
          ((retained_others += 1))
        else
          deleted+=("$generation")
        fi
      done

      printf 'Active generation: %s\n' "$active_generation"
      printf 'Retained generations:'
      printf ' %s' "''${retained[@]}"
      printf '\nDeleted generations:'
      if [[ ''${#deleted[@]} -eq 0 ]]; then
        printf ' none'
      else
        printf ' %s' "''${deleted[@]}"
      fi
      printf '\n'

      if [[ $planning == true ]]; then
        printf 'Planning only; profiles and store were not changed.\n'
        exit 0
      fi

      active_generation_link="$profile-$active_generation-link"
      if ! active_system_now=$(readlink -f /run/current-system) || \
        ! active_generation_system=$(readlink -f -- "$active_generation_link") || \
        [[ $active_system_now != "$active_system" ]] || \
        [[ $active_generation_system != "$active_system" ]]; then
        printf 'Refusing cleanup: the active system changed during planning.\n' >&2
        exit 1
      fi

      if [[ ''${#deleted[@]} -gt 0 ]]; then
        nix-env --profile "$profile" --delete-generations "''${deleted[@]}"
      fi
      nix-store --gc
    '';
  };
in
{
  # fwupd exposes firmware devices and applies only updates explicitly approved
  # through `fwupdmgr`; merely enabling the daemon does not flash anything.
  services.fwupd.enable = true;

  # Make the same program available for a non-destructive `--plan` inspection.
  environment.systemPackages = [ cleanup ];

  systemd.services.helix-nix-cleanup = {
    description = "Trim NixOS generations and collect the Nix store";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${cleanup}/bin/helix-nix-cleanup";
      User = "root";
      Nice = 10;
      IOSchedulingClass = "idle";
      PrivateTmp = true;
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  };

  systemd.timers.helix-nix-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      Persistent = true;
    };
  };

  # Store optimisation hard-links identical files; garbage collection above
  # separately removes paths made unreachable by generation trimming.
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
}
