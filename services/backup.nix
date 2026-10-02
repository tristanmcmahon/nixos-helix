{ pkgs, ... }:

let
  helix = import ../config/helix.nix;
  infernalnexus = import ../config/infernalnexus.nix;
  nas = infernalnexus.shares.nas1.mountPoint;
  passwordFile = "/etc/nixos/secrets/restic-helix";
in
{
  # Nightly, deduplicated, encrypted snapshots of the state a rebuild cannot
  # recreate, kept on Infernalnexus. The reinstall scripts remain the one-shot
  # path for a planned reinstall; this is the routine safety net.
  services.restic.backups.helix = {
    repository = "${nas}/backup/helix-restic";
    inherit passwordFile;
    # Creating the repository on the first run is non-destructive.
    initialize = true;

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

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];
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

  # restic is also the restore tool.
  environment.systemPackages = [ pkgs.restic ];
}
