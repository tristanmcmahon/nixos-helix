{ lib, pkgs, ... }:

let
  baselineConfig = pkgs.writeText "helix-hyprland.conf" ''
    # Helix baseline: deliberately small and safe to replace with a user config.
    monitor = , preferred, auto, 1

    $mainMod = SUPER
    $terminal = ghostty
    $menu = fuzzel

    exec-once = waybar
    exec-once = mako
    exec-once = nm-applet --indicator

    bind = $mainMod, RETURN, exec, $terminal
    bind = $mainMod, D, exec, $menu
    bind = $mainMod, Q, killactive,
    bind = $mainMod SHIFT, E, exec, helix-hyprland-exit
    bind = $mainMod, LEFT, movefocus, l
    bind = $mainMod, RIGHT, movefocus, r
    bind = $mainMod, UP, movefocus, u
    bind = $mainMod, DOWN, movefocus, d

    bind = $mainMod, 1, workspace, 1
    bind = $mainMod, 2, workspace, 2
    bind = $mainMod, 3, workspace, 3
    bind = $mainMod, 4, workspace, 4
    bind = $mainMod, 5, workspace, 5
    bind = $mainMod, 6, workspace, 6
    bind = $mainMod, 7, workspace, 7
    bind = $mainMod, 8, workspace, 8
    bind = $mainMod, 9, workspace, 9
    bind = $mainMod SHIFT, 1, movetoworkspace, 1
    bind = $mainMod SHIFT, 2, movetoworkspace, 2
    bind = $mainMod SHIFT, 3, movetoworkspace, 3
    bind = $mainMod SHIFT, 4, movetoworkspace, 4
    bind = $mainMod SHIFT, 5, movetoworkspace, 5
    bind = $mainMod SHIFT, 6, movetoworkspace, 6
    bind = $mainMod SHIFT, 7, movetoworkspace, 7
    bind = $mainMod SHIFT, 8, movetoworkspace, 8
    bind = $mainMod SHIFT, 9, movetoworkspace, 9

    bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
    bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bindl = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    bindl = , XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

    input {
      kb_layout = us
      follow_mouse = 1
    }

    general {
      layout = dwindle
      gaps_in = 4
      gaps_out = 8
      border_size = 2
    }

    decoration {
      rounding = 6
    }

    animations {
      enabled = false
    }
  '';

  bootstrap = pkgs.writeShellApplication {
    name = "helix-hyprland-session";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
      config_dir="$config_home/hypr"
      config_file="$config_dir/hyprland.conf"

      if [[ ! -e "$config_file" ]]; then
        install -d -m 0700 -- "$config_dir"
        install -m 0600 -- ${baselineConfig} "$config_file"
      fi

      exec ${pkgs.hyprland}/bin/Hyprland "$@"
    '';
  };

  exitPrompt = pkgs.writeShellApplication {
    name = "helix-hyprland-exit";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.hyprland
    ];
    text = ''
      answer=$(printf 'Cancel\nLog out\n' | fuzzel --dmenu --prompt='Hyprland: ')
      if [[ $answer == 'Log out' ]]; then
        hyprctl dispatch exit
      fi
    '';
  };
in
{
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # UWSM supplies the SDDM session and starts the user-owned bootstrap before
  # Hyprland. Existing ~/.config/hypr/hyprland.conf files are left untouched.
  programs.uwsm.waylandCompositors.hyprland.binPath =
    lib.mkForce "${bootstrap}/bin/helix-hyprland-session";

  environment.systemPackages = with pkgs; [
    waybar
    fuzzel
    mako
    networkmanagerapplet
    wl-clipboard
    grim
    slurp
    brightnessctl
    playerctl
    exitPrompt
  ];
}
