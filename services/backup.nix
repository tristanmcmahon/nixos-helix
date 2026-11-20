{ lib, pkgs, ... }:

let
  helix = import ../config/helix.nix;
  helixLib = import ../lib/helix.nix { inherit lib pkgs; };
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
      # Preserve Steam userdata and compatdata (which may contain saves);
      # installed games, workshop payloads and shader caches are replaceable.
      "${helix.home}/.local/share/Steam/steamapps/common"
      "${helix.home}/.local/share/Steam/steamapps/downloading"
      "${helix.home}/.local/share/Steam/steamapps/shadercache"
      "${helix.home}/.local/share/Steam/steamapps/workshop"
      "${helix.home}/.local/share/Steam/steamrt64"
      "${helix.home}/.local/share/Steam/ubuntu12_32/steam-runtime"
      "${helix.home}/.local/share/Steam/ubuntu12_32/steam-runtime.old"
      "${helix.home}/.local/share/Steam/config/htmlcache"
      "**/node_modules"
      "**/.direnv"
      "**/result"
    ];
    extraBackupArgs = [ "--one-file-system" ];

    # Deduplicated Restic retention is independent of hamology tar archives.
    pruneOpts = backups.resticRetention;
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
    # unit is skipped rather than failed. The NAS is optional: Wants (not
    # Requires) keeps the ordering after the mount, but an offline NAS lets
    # the run start and fail, so it raises an alert and shows in helix-health
    # instead of ending as a silent dependency failure. With initialize off, a
    # missing mount can never create a repository on the local disk.
    unitConfig = {
      ConditionPathExists = passwordFile;
      WantsMountsFor = [ nas ];
    };
    serviceConfig = {
      Nice = 19;
      IOSchedulingClass = "idle";
      # See lib/helix.nix: no restart on failure, so a failed run alerts.
      ExecStartPre = [ helixLib.waitForInfernalnexusCommand ];
    };
  };

  helix.failureAlerts.units = [ "restic-backups-helix.service" ];

  # restic is also the restore tool.
  environment.systemPackages = [ pkgs.restic ];
}
