{ pkgs, ... }:

let
  helix = import ../config/helix.nix;
  inherit ((import ../config/infernalnexus.nix).backups) keep;
  inherit (helix) user home;
  repo = "${home}/Projects/hamology";
  entrypoint = "${repo}/scripts/hamology-backup";
in
{
  # Thin adapter: hamology owns what a backup contains and how it is verified.
  # Helix only decides when it runs. The NAS side is authorised once with
  # `hamology-backup --install-unattended`; until then runs fail visibly and
  # never prompt. Infernalnexus is optional, so nothing here gates boot.
  systemd.user.services.hamology-backup = {
    description = "hamology recoverable-state backup (kept on Infernalnexus)";

    unitConfig = {
      ConditionUser = user;
      ConditionPathExists = entrypoint;
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
      WorkingDirectory = repo;
      ExecStart = "${pkgs.bash}/bin/bash ${entrypoint} --unattended --keep ${toString keep}";
      Nice = 19;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "3h";
      NoNewPrivileges = true;
    };
  };

  systemd.user.timers.hamology-backup = {
    description = "Nightly hamology backup";
    wantedBy = [ "timers.target" ];

    unitConfig.ConditionUser = user;

    timerConfig = {
      OnCalendar = "04:23";
      RandomizedDelaySec = "30min";
      Persistent = true;
      Unit = "hamology-backup.service";
    };
  };
}
