{
  config,
  lib,
  pkgs,
  ...
}:

let
  helix = import ../config/helix.nix;
  cfg = config.helix.failureAlerts;
  alert = pkgs.writeShellApplication {
    name = "helix-failure-alert";
    runtimeInputs = with pkgs; [
      coreutils
      libnotify
      systemd
      util-linux
    ];
    text = ''
      helix_user=${lib.escapeShellArg helix.user}
      watched_units=(${lib.escapeShellArgs cfg.units})
      watched_user_units=(${lib.escapeShellArgs cfg.userUnits})
    ''
    + builtins.readFile ../scripts/helix-failure-alert.sh;
  };
  onFailure =
    units:
    lib.genAttrs (map (lib.removeSuffix ".service") units) (_: {
      onFailure = [ "helix-failure-alert@%n.service" ];
    });
  # %i, not %I: the instance is the failed unit's name, and unescaping would
  # turn its dashes into slashes.
  template = {
    description = "Report the failure of %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${alert}/bin/helix-failure-alert %i";
    };
  };
in
{
  # Units that run unattended (backups, maintenance) would otherwise fail
  # silently until someone ran helix-health. Each feature registers its own
  # units, as it does for the health gate, so disabling a feature drops them.
  options.helix.failureAlerts = {
    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "System services whose failure raises a desktop notification.";
    };
    userUnits = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "User services whose failure raises a desktop notification.";
    };
  };

  config = {
    # OnFailure is attached through systemd.services, so only services work.
    assertions = [
      {
        assertion = builtins.all (lib.hasSuffix ".service") (cfg.units ++ cfg.userUnits);
        message = "helix.failureAlerts lists only .service units.";
      }
    ];

    environment.systemPackages = [ alert ];

    systemd.services = onFailure cfg.units // {
      "helix-failure-alert@" = template;
    };

    systemd.user.services = onFailure cfg.userUnits // {
      "helix-failure-alert@" = template;

      # A failure while nobody is logged in (the nightly backups) has no
      # session to notify, so each login reports whatever is still failed.
      # `systemctl reset-failed UNIT` clears an acknowledged failure.
      helix-failure-alert-pending = {
        description = "Report watched units that are still failed";
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        unitConfig.ConditionUser = helix.user;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${alert}/bin/helix-failure-alert --pending";
        };
      };
    };
  };
}
