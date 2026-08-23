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
}
