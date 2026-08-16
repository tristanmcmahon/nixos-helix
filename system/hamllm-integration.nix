{
  pkgs,
  lib,
  ...
}:

with lib;

let
  service_name = "hamllm-bridge";
in

{
  environment.systemPackages = with pkgs; [ (import ../packages/hamllm.nix) ];

  systemd.user.services."${service_name}" = {
    description = "hamllM mail bridge - oneshot";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 -m hamllm.bridge";
      User = "tristan";
    };
    wantedBy = [ "default.target" ];
  };

  systemd.user.timers."${service_name}-timer" = {
    description = "Poll hamLLM every minute";
    timerConfig = {
      OnUnitActiveSec = "60s";
      Persistent = true;
    };
    wantedBy = [ "timers.target" ];
  };
}
