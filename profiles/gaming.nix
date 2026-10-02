{
  config,
  lib,
  pkgs,
  utils,
  ...
}:

let
  helix = import ../config/helix.nix;
  helixLib = import ../lib/helix.nix { inherit lib pkgs utils; };
  cfg = config.helix.gaming;
  doomRoot = "${helix.gamesNvme.mountPoint}/doom";
  doomRunnerCommand = pkgs.writeShellApplication {
    name = "doomrunner";
    runtimeInputs = with pkgs; [
      coreutils
      doomrunner
      jq
    ];
    text = ''
      options="''${XDG_DATA_HOME:-"$HOME/.local/share"}/DoomRunner/options.json"
      if [[ -f $options ]] && jq -e 'type == "object"' "$options" >/dev/null 2>&1; then
        options_tmp=$(mktemp "$options.XXXXXX")
        if jq '
          (.engines.engine_list // [] |
            map(select(
              .id == "8b9019b0-6141-4e08-a5dd-helixgzdoom" or
              .path == "/run/current-system/sw/bin/gzdoom"
            ) | .id)
          ) as $gzdoom_ids |
          .presets = ((.presets // []) | map(
            if (.selected_engine as $engine | ($gzdoom_ids | index($engine)) != null)
            then .additional_args = (
              (.additional_args // "") |
              if test("(^|[[:space:]])\\+vid_preferbackend([[:space:]]+|=)[0-9]+")
              then gsub("\\+vid_preferbackend([[:space:]]+|=)[0-9]+"; "+vid_preferbackend 1")
              else . + (if length == 0 then "" else " " end) + "+vid_preferbackend 1"
              end
            )
            else .
            end
          ))
        ' "$options" > "$options_tmp"; then
          chmod --reference="$options" "$options_tmp"
          mv "$options_tmp" "$options"
        else
          rm -f "$options_tmp"
        fi
      fi
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
  options.helix.gaming.enable = lib.mkEnableOption "Steam, Proton tooling and Doom";

  config = lib.mkIf cfg.enable {
    # Steam's NixOS integration installs the client and its controller udev rules.
    programs = {
      steam.enable = true;
      gamemode.enable = true;
      gamescope = {
        enable = true;
        capSysNice = false;
      };
    };
    hardware.graphics.enable32Bit = true;
    services.pipewire.alsa.support32Bit = true;

    environment.systemPackages = with pkgs; [
      adwsteamgtk
      doomrunner
      doomRunnerCommand
      doomSetup
      gzdoom
      mangohud
      protonplus
      protontricks
      goverlay
      uzdoom
    ];

    environment.sessionVariables.DOOMWADDIR = "${doomRoot}/iwads";

    systemd.services.helix-doom-storage = helixLib.mkMountedDirectory {
      description = "Create the Doom library on GAMES_NVME";
      inherit (helix.gamesNvme) mountPoint;
      path = doomRoot;
      owner = helix.user;
      inherit (helix) group;
      mode = "0775";
    };
  };
}
