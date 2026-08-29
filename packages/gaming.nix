{ pkgs, ... }:

let
  doomSetup = pkgs.writeShellApplication {
    name = "helix-doom-setup";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      findutils
      p7zip
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
    doomSetup
    gzdoom
    mangohud
    uzdoom
  ];

  environment.sessionVariables.DOOMWADDIR = "/mnt/games_nvme/doom/iwads";
}
