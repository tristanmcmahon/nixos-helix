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
  gameBenchmarkHistory = pkgs.writeShellApplication {
    name = "helix-game-benchmarks";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${../scripts/helix-game-benchmarks.py} "$@"
    '';
  };
  # The SSD list comes from config/helix.nix so the script never repeats it.
  falloutLondonSetup = pkgs.writeShellApplication {
    name = "helix-fallout-london-setup";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      procps
      util-linux
    ];
    text = ''
      export HELIX_SSD_ROOTS=${
        lib.escapeShellArg (lib.concatMapStringsSep " " (ssd: "${ssd.id}=${ssd.mountPoint}") helix.ssds)
      }
    ''
    + builtins.readFile ../scripts/helix-fallout-london-setup.sh;
  };
in
{
  options.helix.gaming.enable = lib.mkEnableOption "Steam, Proton tooling and Doom";

  config = lib.mkIf cfg.enable {
    # Steam's NixOS integration installs the client and its controller udev rules.
    programs = {
      steam = {
        enable = true;
        # Steam-scoped MangoHud activation: don't change the global desktop
        # environment or edit any game's Steam launch options.
        package = pkgs.steam.override {
          extraEnv = {
            MANGOHUD = "1";
            # OpenGL needs the loader shim rather than Vulkan's implicit layer.
            MANGOHUD_DLSYM = "1";
            MANGOHUD_CONFIG = "autostart_log=5,log_duration=0,log_interval=100,output_folder=${helix.home}/.local/state/helix/game-benchmarks,permit_upload=0";
          };
          # `extraProfile` renders into the exact same generated FHS profile
          # script as `extraEnv` (nixpkgs steam package.nix: both land in one
          # `set -a; <extraEnv>; set +a; <extraProfile>` block), so it cannot
          # reach OpenGL games any differently than extraEnv does — confirmed
          # by live process inspection: MANGOHUD=1 (extraEnv) survives into
          # the game process every time, but a prior extraProfile-based
          # `export LD_PRELOAD=libMangoHud_shim.so` never did, at any point
          # in the launch chain. `mangohud %command%` (Steam's own supported
          # wrapper pattern) does work, because it execs as the immediate
          # parent of Steam's per-game launch (reaper/pressure-vessel), with
          # no intervening client-startup step to discard it.
          #
          # extraBwrapArgs sets these directly on bubblewrap's container-init
          # process (bypassing FHS profile scripts and Steam's own internal
          # LD_LIBRARY_PATH handling in steam.sh) so the values are ambient
          # from the very first process in the sandbox, same as a %command%
          # wrapper would provide, without touching any game's launch
          # options. Absolute paths avoid relying on LD_LIBRARY_PATH-based
          # bare-filename resolution for LD_PRELOAD specifically.
          extraBwrapArgs = [
            "--setenv LD_PRELOAD ${pkgs.mangohud}/lib/mangohud/libMangoHud_shim.so:${pkgs.pkgsi686Linux.mangohud}/lib/mangohud/libMangoHud_shim.so"
            "--setenv LD_LIBRARY_PATH ${pkgs.mangohud}/lib/mangohud:${pkgs.pkgsi686Linux.mangohud}/lib/mangohud"
            "--setenv XDG_DATA_DIRS ${pkgs.mangohud}/share"
          ];
        };
      };
      gamemode.enable = true;
      gamescope = {
        enable = true;
        capSysNice = false;
      };
    };
    # User tmpfiles creates a private writable log directory at login.
    systemd.user.tmpfiles.rules = [
      "d %h/.local/state/helix/game-benchmarks 0700 - - -"
    ];
    hardware.graphics.enable32Bit = true;
    services.pipewire.alsa.support32Bit = true;

    environment.systemPackages = with pkgs; [
      adwsteamgtk
      doomrunner
      doomRunnerCommand
      doomSetup
      falloutLondonSetup
      gameBenchmarkHistory
      gzdoom
      heroic
      # Lutris for Battle.net: Blizzard ships no native Linux client, and
      # Lutris's maintained community installer is the standard path. Lutris
      # manages its own Wine runner (fetched to ~/.local/share/lutris on
      # first use, never the Nix store or build time), so no separate Wine
      # package is installed here; winetricks is the one dependency Lutris
      # genuinely needs from outside its own runner management.
      lutris
      winetricks
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
