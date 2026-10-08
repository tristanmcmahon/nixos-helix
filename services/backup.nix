{ pkgs, ... }:

let
  helix = import ../config/helix.nix;
  infernalnexus = import ../config/infernalnexus.nix;
  nas = infernalnexus.shares.nas1.mountPoint;
  inherit (infernalnexus) backups;
  passwordFile = "/etc/nixos/secrets/restic-helix";
in
{
  # Nightly, deduplicated, encrypted snapshots of the state a rebuild cannot
  # recreate, kept on Infernalnexus. The reinstall scripts remain the one-shot
  # path for a planned reinstall; this is the routine safety net.
  services.restic.backups.helix = {
    repository = backups.restic;
    inherit passwordFile;
    # The repository already exists and is never created implicitly: a
    # missing repository (an unmigrated move, a wrong path) fails visibly
    # instead of silently starting an empty one. docs/backup.md has the
    # one-time init for a new repository.
    initialize = false;

    paths = [
      helix.home
      "/etc/nixos/secrets"
      "/etc/ssh"
      "/etc/NetworkManager/system-connections"
    ];
    exclude = [
      "${helix.home}/.cache"
      "${helix.home}/.local/share/Trash"
      "${helix.home}/.local/share/Steam"
      "${helix.home}/.steam"
      "**/node_modules"
      "**/.direnv"
      "**/result"
    ];
    extraBackupArgs = [ "--one-file-system" ];

    # The same retention as the hamology archives beside it.
    pruneOpts = [ "--keep-last ${toString backups.keep}" ];
    # A light structural check after pruning; full data reads are a manual drill.
    runCheck = true;

    timerConfig = {
      OnCalendar = "03:17";
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };

  systemd.services.restic-backups-helix = {
    # The password is created by hand (see docs/backup.md); until it exists the
    # unit is skipped rather than failed. The NAS is optional: if it is offline
    # the run fails visibly in helix-health and Persistent retries next boot.
    unitConfig = {
      ConditionPathExists = passwordFile;
      RequiresMountsFor = [ nas ];
    };
    serviceConfig = {
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  helix.failureAlerts.units = [ "restic-backups-helix.service" ];

  # restic is also the restore tool.
  environment.systemPackages = [ pkgs.restic ];
}
