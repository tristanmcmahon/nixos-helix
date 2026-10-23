{ pkgs, ... }:

let
  helix = import ../config/helix.nix;
  inherit ((import ../config/infernalnexus.nix).backups) keep;
  inherit (helix) user group home;
  repo = "${home}/Projects/hamology";
  entrypoint = "${repo}/scripts/hamology-backup";
in
{
  # Thin adapter: hamology owns what a backup contains and how it is verified.
  # Helix only decides when it runs. The NAS side is authorised once with
  # `hamology-backup --install-unattended`; until then runs fail visibly and
  # never prompt. Infernalnexus is optional, so nothing here gates boot.
  #
  # A system unit running as the user, rather than a user unit, so the nightly
  # run does not depend on a login session. User lingering would also do that,
  # but it would start every other user unit (the OpenClaw gateway, hamSteam
  # maintenance) at boot without a login.
  systemd.services.hamology-backup = {
    description = "hamology recoverable-state backup (kept on Infernalnexus)";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];

    unitConfig = {
      ConditionPathExists = entrypoint;
      # A resume from suspend fires this Persistent timer's missed run before
      # Wi-Fi has reconnected (network-online.target is a boot-only gate; it
      # is not re-evaluated after resume). hamology-backup has no retry of
      # its own, unlike restic, so it loses that race every time without
      # this. Bounded: a few attempts over a couple of minutes, matching the
      # NAS mount's own widened start-limit above it.
      StartLimitIntervalSec = "3min";
      StartLimitBurst = 4;
    };

    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnutar
      pkgs.gzip
      pkgs.openssh
      pkgs.python3
    ];

    environment.HOME = home;

    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = group;
      WorkingDirectory = repo;
      ExecStart = "${pkgs.bash}/bin/bash ${entrypoint} --unattended --keep ${toString keep}";
      Nice = 19;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "3h";
      NoNewPrivileges = true;
      # Retry a resume-triggered run that fails before Wi-Fi reconnects;
      # see the StartLimit comment above. hamology's own backup script stays
      # the single source of truth for whether a run actually succeeded.
      Restart = "on-failure";
      RestartSec = "20s";
    };
  };

  helix.failureAlerts.units = [ "hamology-backup.service" ];

  systemd.timers.hamology-backup = {
    description = "Nightly hamology backup";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "04:23";
      RandomizedDelaySec = "30min";
      Persistent = true;
      Unit = "hamology-backup.service";
    };
  };
}
