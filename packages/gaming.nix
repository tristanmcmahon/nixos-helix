{ pkgs, ... }:

let
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

  environment.sessionVariables.DOOMWADDIR = "/mnt/games_nvme/doom/iwads";
}
