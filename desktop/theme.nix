{ pkgs, ... }:

let
  themeDirectory = ../config/theme;
  palette = import ../config/theme/palette.nix;
  themes = [
    "fern"
    "petrol"
    "plum"
    "oxide"
    "amber"
    "rosewood"
    "hotdog"
  ];
  themeFamily = pkgs.runCommand "helix-theme-family" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    python3 ${../scripts/generate-theme-family.py} ${themeDirectory} ${../config/ghostty/profiles/main.ghostty} $out/generated
    for theme in ${builtins.concatStringsSep " " themes}; do
      colors=$(find "$out/generated/$theme" -maxdepth 1 -name '*.colors')
      scheme_name=$(basename "$colors" .colors)
      install -Dm444 "$colors" "$out/share/color-schemes/$scheme_name.colors"
      install -Dm444 "$out/generated/$theme/$scheme_name.colorscheme" "$out/share/konsole/$scheme_name.colorscheme"
      install -Dm444 "$out/generated/$theme/$scheme_name.profile" "$out/share/konsole/$scheme_name.profile"
      install -Dm444 "$out/generated/$theme/wallpaper.svg" \
        "$out/share/wallpapers/$scheme_name/contents/images/wallpaper.svg"
    done
  '';
  fernWallpaper = "${themeFamily}/share/wallpapers/HelixGraphiteFern/contents/images/wallpaper.svg";
  sddmTheme = pkgs.runCommand "sddm-theme-helix-graphite-fern" { } ''
    mkdir -p $out/share/sddm/themes/helix-graphite-fern
    cp -r ${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze/. \
      $out/share/sddm/themes/helix-graphite-fern/
    chmod -R u+w $out/share/sddm/themes/helix-graphite-fern
    cat > $out/share/sddm/themes/helix-graphite-fern/theme.conf <<EOF
    [General]
    showlogo=hidden
    showClock=true
    type=image
    color=${palette.background}
    fontSize=10
    background=${fernWallpaper}
    needsFullUserModel=false
    EOF
  '';
  helixTheme = pkgs.writeShellApplication {
    name = "helix-theme";
    runtimeInputs = with pkgs; [
      coreutils
      dconf
      glib
      kdePackages.kconfig
      kdePackages.plasma-workspace
      procps
      python3
      systemd
    ];
    text = ''
      export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/helix"
      selection_file="$state_dir/theme"

      describe() {
        printf '%-10s %s\n' fern 'graphite with restrained fern green (default)'
        printf '%-10s %s\n' petrol 'muted deep petrol and teal'
        printf '%-10s %s\n' plum 'dusty aubergine and plum'
        printf '%-10s %s\n' oxide 'muted rust and copper'
        printf '%-10s %s\n' amber 'desaturated ochre and gold'
        printf '%-10s %s\n' rosewood 'dark wine and rosewood'
        printf '%-10s %s\n' hotdog 'regrettably available.'
      }
      selected=fern
      [[ -r $selection_file ]] && read -r selected < "$selection_file"
      case $selected in fern|petrol|plum|oxide|amber|rosewood|hotdog) ;; *) selected=fern ;; esac

      case ''${1:-} in
      list) describe; exit 0 ;;
      current) printf '%s\n' "$selected"; exit 0 ;;
      fern|petrol|plum|oxide|amber|rosewood|hotdog) selected=$1 ;;
      random)
        pool=(fern petrol plum oxide amber rosewood)
        eligible=()
        for candidate in "''${pool[@]}"; do
          [[ $candidate == "$selected" ]] || eligible+=("$candidate")
        done
        index=$((RANDOM % ''${#eligible[@]}))
        selected="''${eligible[$index]}"
        ;;
      --apply-current) ;;
      --help|-h|"") printf 'Usage: helix-theme {list|current|random|fern|petrol|plum|oxide|amber|rosewood|hotdog}\n'; exit 0 ;;
      *) printf 'Unknown Helix theme: %s\n' "$1" >&2; exit 2 ;;
      esac

      source=/etc/helix/themes/$selected
      [[ -d $source ]] || { printf 'Theme assets unavailable: %s\n' "$source" >&2; exit 1; }
      mkdir -p "$state_dir" "$XDG_CONFIG_HOME/helix/theme" "$XDG_CONFIG_HOME/waybar" \
        "$XDG_CONFIG_HOME/mako" "$XDG_CONFIG_HOME/fuzzel" "$XDG_CONFIG_HOME/ghostty" \
        "$XDG_CONFIG_HOME/AdwSteamGtk"
      printf '%s\n' "$selected" > "$selection_file"
      ln -sfn "$source" "$XDG_CONFIG_HOME/helix/theme/current"
      install -m 0644 "$source/waybar.css" "$XDG_CONFIG_HOME/waybar/helix.css"
      install -m 0644 "$source/mako.conf" "$XDG_CONFIG_HOME/mako/helix.conf"
      install -m 0644 "$source/fuzzel.ini" "$XDG_CONFIG_HOME/fuzzel/helix.ini"
      install -m 0644 "$source/steam.css" "$XDG_CONFIG_HOME/AdwSteamGtk/custom.css"
      install -m 0644 "$source/ghostty.ghostty" "$XDG_CONFIG_HOME/ghostty/profile.ghostty"
      python3 /etc/helix/theme/apply-theme-settings.py merge-ini \
        /etc/helix/theme/gtk-3.0-settings.ini "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
      python3 /etc/helix/theme/apply-theme-settings.py merge-ini \
        /etc/helix/theme/gtk-4.0-settings.ini "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"

      if [[ -n ''${DBUS_SESSION_BUS_ADDRESS:-} && -n ''${XDG_CURRENT_DESKTOP:-} ]]; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark
        gsettings set org.gnome.desktop.interface gtk-theme Breeze-Dark
        gsettings set org.gnome.desktop.interface icon-theme breeze-dark
        if gsettings writable io.github.Foldex.AdwSteamGtk prefs-install-custom-css >/dev/null 2>&1; then
          gsettings set io.github.Foldex.AdwSteamGtk prefs-install-custom-css true
        fi
        if [[ $XDG_CURRENT_DESKTOP == *KDE* ]]; then
          if [[ $selected == hotdog ]]; then
            scheme=HelixGraphiteHotDogStand
          else
            pretty="$(tr '[:lower:]' '[:upper:]' <<<"''${selected:0:1}")''${selected:1}"
            scheme="HelixGraphite$pretty"
          fi
          plasma-apply-desktoptheme breeze-dark
          kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze
          kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
          kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Breeze
          kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize Tiny
          kwriteconfig6 --file breezerc --group Common --key OutlineIntensity 35
          kwriteconfig6 --file breezerc --group Common --key ShadowStrength 180
          plasma-apply-colorscheme "$scheme"
          plasma-apply-wallpaperimage "$source/wallpaper.svg"
          kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile "$scheme.profile"
        fi
        systemctl --user reload app-com.mitchellh.ghostty.service 2>/dev/null || pkill -USR2 -x ghostty 2>/dev/null || true
        pkill -USR2 -x waybar 2>/dev/null || true
        makoctl reload 2>/dev/null || true
      fi
      printf 'Applied Helix Graphite + %s. Restart Steam for its custom CSS to take effect.\n' "$selected"
    '';
  };
  applyTheme = pkgs.writeShellApplication {
    name = "helix-apply-theme";
    runtimeInputs = [ helixTheme ];
    text = ''
      case ''${1:-} in
      ""|--force) exec helix-theme fern ;;
      --help|-h) printf 'Usage: helix-apply-theme [--force|--help]\n' ;;
      *) printf 'Usage: helix-apply-theme [--force|--help]\n' >&2; exit 2 ;;
      esac
    '';
  };
  applySteamTheme = pkgs.writeShellApplication {
    name = "helix-apply-steam-theme";
    runtimeInputs = [
      pkgs.adwsteamgtk
      pkgs.coreutils
      pkgs.glib
      pkgs.procps
    ];
    text = ''
      if [[ ''${1:-} == --help ]]; then
        printf 'Usage: helix-apply-steam-theme\nClose Steam first; the current Helix palette will be installed.\n'
        exit 0
      fi
      [[ $# -eq 0 ]] || { printf 'Usage: helix-apply-steam-theme\n' >&2; exit 2; }
      if pgrep -x steam >/dev/null || pgrep -x steamwebhelper >/dev/null; then
        printf 'Close Steam completely before applying its theme.\n' >&2
        exit 1
      fi
      current="''${XDG_CONFIG_HOME:-$HOME/.config}/helix/theme/current/steam.css"
      [[ -r $current ]] || current=/etc/helix/theme/steam.css
      install -Dm644 "$current" "''${XDG_CONFIG_HOME:-$HOME/.config}/AdwSteamGtk/custom.css"
      if gsettings writable io.github.Foldex.AdwSteamGtk prefs-install-custom-css >/dev/null 2>&1; then
        gsettings set io.github.Foldex.AdwSteamGtk prefs-install-custom-css true
      else
        printf 'AdwSteamGtk settings schema is unavailable; continuing with CSS installation.\n' >&2
      fi
      adwaita-steam-gtk --install --options \
        'color_theme:oled;rounded_corners:false;win_controls:windows;win_controls_layout:auto'
      printf 'Applied the current Helix Steam skin. Start Steam to inspect it.\n'
    '';
  };
in
{
  programs.dconf.enable = true;
  services.displayManager.sddm.theme = "helix-graphite-fern";
  environment.systemPackages = [
    themeFamily
    pkgs.kdePackages.breeze-gtk
    pkgs.kdePackages.breeze-icons
    pkgs.kdePackages.kconfig
    helixTheme
    applyTheme
    applySteamTheme
    sddmTheme
  ];
  environment.etc =
    builtins.listToAttrs (
      map (theme: {
        name = "helix/themes/${theme}";
        value.source = "${themeFamily}/generated/${theme}";
      }) themes
    )
    // {
      "helix/theme/gtk-3.0-settings.ini".source = ../config/theme/gtk-3.0-settings.ini;
      "helix/theme/gtk-4.0-settings.ini".source = ../config/theme/gtk-4.0-settings.ini;
      "helix/theme/waybar.css".source = "${themeFamily}/generated/fern/waybar.css";
      "helix/theme/mako.conf".source = "${themeFamily}/generated/fern/mako.conf";
      "helix/theme/fuzzel.ini".source = "${themeFamily}/generated/fern/fuzzel.ini";
      "helix/theme/steam.css".source = "${themeFamily}/generated/fern/steam.css";
      "helix/theme/wallpaper.svg".source = "${themeFamily}/generated/fern/wallpaper.svg";
      "helix/theme/apply-theme-settings.py".source = ../scripts/apply-theme-settings.py;
      "xdg/autostart/helix-theme.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Helix Theme
        Comment=Choose a new civilized Helix theme after Plasma starts
        Exec=${helixTheme}/bin/helix-theme random
        OnlyShowIn=KDE;
        NoDisplay=true
      '';
    };
  systemd.user.services.helix-graphite-fern-theme = {
    description = "Apply Tristan's persisted Helix theme";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session-pre.target" ];
    unitConfig.ConditionUser = "tristan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${helixTheme}/bin/helix-theme --apply-current";
      Environment = [
        "HOME=/home/tristan"
        "XDG_CONFIG_HOME=/home/tristan/.config"
      ];
    };
  };
}
