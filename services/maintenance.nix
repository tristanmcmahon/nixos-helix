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
        2)
          if [[ $1 != --plan ]]; then
            printf 'Usage: helix-nix-cleanup [--plan GENERATION_LISTING]\n' >&2
            exit 2
          fi
          planning=true
          listing=$2
          ;;
        *)
          printf 'Usage: helix-nix-cleanup [--plan GENERATION_LISTING]\n' >&2
          exit 2
          ;;
      esac

      mapfile -t current_generations < <(
        awk '$1 ~ /^[0-9]+$/ && $NF == "(current)" { print $1 }' "$listing"
      )
      if [[ ''${#current_generations[@]} -ne 1 ]]; then
        printf 'Refusing cleanup: expected exactly one current generation, found %s.\n' \
          "''${#current_generations[@]}" >&2
        exit 1
      fi
      current=''${current_generations[0]}

      mapfile -t generations < <(
        awk '$1 ~ /^[0-9]+$/ { print $1 }' "$listing" | sort -nr
      )

      retained=("$current")
      deleted=()
      retained_others=0
      for generation in "''${generations[@]}"; do
        if [[ $generation == "$current" ]]; then
          continue
        fi
        if [[ $retained_others -lt 2 ]]; then
          retained+=("$generation")
          ((retained_others += 1))
        else
          deleted+=("$generation")
        fi
      done

      printf 'Current generation: %s\n' "$current"
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
