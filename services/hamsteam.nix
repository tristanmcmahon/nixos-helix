{ lib, pkgs, ... }:

let
  user = "tristan";
  home = "/home/${user}";
  repo = "${home}/Projects/hamSteam";
  entrypoint = "${repo}/hamsteam.py";
in
{
  # nixos-helix owns hamSteam's lifecycle. hamSteam remains a separately
  # developed checkout; this module owns when and how its quiet maintainer runs.
  systemd.user.services.hamsteam-maintain = {
    description = "hamSteam quiet Steam storage maintenance";

    unitConfig = {
      ConditionUser = user;
      ConditionPathExists = entrypoint;
    };

    environment = {
      HOME = home;
      PATH = lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.procps
        pkgs.python3
        pkgs.steam
        pkgs.util-linux
      ];
    };

    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = repo;
      ExecStart = "${pkgs.python3}/bin/python ${entrypoint} service";

      # Storage housekeeping should always yield to interactive work and games.
      Nice = 19;
      CPUSchedulingPolicy = "batch";
      CPUWeight = 1;
      IOSchedulingClass = "idle";
      IOSchedulingPriority = 7;
      IOWeight = 1;
      OOMScoreAdjust = 500;

      # Healthy no-op runs are silent. The service itself emits only maintenance
      # summaries and safety/errors on stderr.
      StandardOutput = "null";
      StandardError = "journal";
      TimeoutStartSec = "4h";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      RestrictSUIDSGID = true;
    };
  };

  systemd.user.timers.hamsteam-maintain = {
    description = "Periodically offer hamSteam a quiet maintenance window";
    wantedBy = [ "timers.target" ];

    unitConfig.ConditionUser = user;

    timerConfig = {
      OnStartupSec = "15min";
      OnUnitInactiveSec = "4h";
      RandomizedDelaySec = "45min";
      AccuracySec = "15min";
      Persistent = true;
      Unit = "hamsteam-maintain.service";
    };
  };

  # One-time ownership migration. The earlier hamSteam installer placed repo
  # symlinks in ~/.config/systemd/user, which outrank /etc/systemd/user. Remove
  # only links that resolve back into this hamSteam checkout; leave any unrelated
  # user-managed unit with the same name untouched.
  system.activationScripts.hamsteamLegacyUserUnitCleanup.text = ''
    legacy_dir=${home}/.config/systemd/user
    for relative in \
      hamsteam-maintain.service \
      hamsteam-maintain.timer \
      timers.target.wants/hamsteam-maintain.timer; do
      path="$legacy_dir/$relative"
      if [ -L "$path" ]; then
        target="$(${pkgs.coreutils}/bin/readlink -f "$path" || true)"
        case "$target" in
          ${repo}/systemd/hamsteam-maintain.service|${repo}/systemd/hamsteam-maintain.timer)
            ${pkgs.coreutils}/bin/rm -f "$path"
            ;;
        esac
      fi
    done
  '';
}
