{ pkgs, ... }:

let
  doomRunnerCommand = pkgs.writeShellApplication {
    name = "doomrunner";
    runtimeInputs = [ pkgs.doomrunner ];
    text = ''
      exec DoomRunner "$@"
    '';
  };

  doomSetup = pkgs.writeShellApplication {
    name = "helix-doom-setup";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      findutils
      gnused
      jq
      procps
      unzip
      util-linux
    ];
    text = builtins.readFile ../scripts/helix-doom-setup.sh;
  };
in
{
  environment.systemPackages = with pkgs; [
    adwsteamgtk
    doomrunner
    doomRunnerCommand
    doomSetup
    gzdoom
    mangohud
    uzdoom
  ];

  environment.sessionVariables.DOOMWADDIR = "/mnt/games_nvme/doom/iwads";
}
