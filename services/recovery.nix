{ pkgs, ... }:

let
  receipt = pkgs.writeShellApplication {
    name = "helix-recovery-receipt";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = builtins.readFile ../scripts/helix-recovery-receipt.sh;
  };
  status = pkgs.writeShellApplication {
    name = "helix-recovery";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = builtins.readFile ../scripts/helix-recovery.sh;
  };
in
{
  # Successful ExecStartPost is the only way to refresh a receipt. A failed or
  # ConditionPathExists-skipped backup does not produce false success.
  # The + prefix runs this narrow receipt writer as root even though the
  # hamology backup itself runs as the unprivileged desktop user.
  systemd.services.restic-backups-helix.serviceConfig.ExecStartPost = [
    "+${receipt}/bin/helix-recovery-receipt restic"
  ];
  systemd.services.hamology-backup.serviceConfig.ExecStartPost = [
    "+${receipt}/bin/helix-recovery-receipt hamology"
  ];

  environment.systemPackages = [ status ];

  # Audit only local, persistent receipts. A missing NAS must never hang this
  # unit or influence the NAS-independent helix-health --check boot gate.
  systemd.services.helix-recovery-audit = {
    description = "Audit recency of Helix recoverable-state backups";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${status}/bin/helix-recovery --check";
    };
  };
  systemd.timers.helix-recovery-audit = {
    description = "Check Helix backup freshness daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "09:15";
      RandomizedDelaySec = "30min";
      Persistent = true;
      Unit = "helix-recovery-audit.service";
    };
  };
  helix.failureAlerts.units = [ "helix-recovery-audit.service" ];
}
