{ pkgs, ... }:

let
  themeSessionStart = pkgs.writeShellApplication {
    name = "helix-hyprland-theme-start";
    runtimeInputs = [
      pkgs.mako
      pkgs.swaybg
      pkgs.waybar
    ];
    text = ''
      /run/current-system/sw/bin/helix-theme random || true
      swaybg --image /home/tristan/.config/helix/theme/current/wallpaper.svg --mode fill &
      waybar --style /home/tristan/.config/helix/theme/current/waybar.css &
      mako --config /home/tristan/.config/helix/theme/current/mako.conf &
      wait
    '';
  };

  baselineConfig = ''
    # Helix baseline: deliberately small and owned by this repository.
    monitor = , preferred, auto, 1

    $mainMod = SUPER
    $terminal = ghostty
    $menu = fuzzel --config /home/tristan/.config/helix/theme/current/fuzzel.ini

    exec-once = helix-hyprland-theme-start
    exec-once = nm-applet --indicator
    exec-once = ${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1

    bind = $mainMod, RETURN, exec, $terminal
    bind = $mainMod SHIFT, RETURN, exec, ghostty-profile
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
      col.active_border = rgb(67B87A)
      col.inactive_border = rgb(3A443C)
    }

    decoration {
      rounding = 6
    }

    animations {
      enabled = false
    }
  '';

  exitPrompt = pkgs.writeShellApplication {
    name = "helix-hyprland-exit";
    runtimeInputs = [
      pkgs.fuzzel
      pkgs.hyprland
    ];
    text = ''
      answer=$(printf 'Cancel\nLog out\n' |
        fuzzel --config /etc/helix/theme/fuzzel.ini --dmenu --prompt='Hyprland: ')
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

  # UWSM keeps the standard compositor path and selects the immutable baseline
  # explicitly. Hyprland never needs to create or update a user config file.
  programs.uwsm.waylandCompositors.hyprland = {
    prettyName = "Hyprland";
    comment = "Hyprland compositor managed by UWSM";
    binPath = "/run/current-system/sw/bin/Hyprland";
    extraArgs = [
      "--config"
      "/etc/hypr/helix.conf"
    ];
  };

  environment.etc."hypr/helix.conf".text = baselineConfig;

  environment.systemPackages = with pkgs; [
    waybar
    fuzzel
    mako
    swaybg
    networkmanagerapplet
    exitPrompt
    themeSessionStart
  ];
}
