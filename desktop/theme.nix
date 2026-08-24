{
  lib,
  pkgs,
  ...
}:

let
  host = import ../config/host.nix;
  themeDirectory = ../config/theme;
  palette = import ../config/theme/palette.nix;
  wallpaper = "${themePackage}/share/wallpapers/HelixGraphiteFern/contents/images/wallpaper.svg";
  themeRevision = builtins.hashString "sha256" (
    builtins.concatStringsSep "" (
      map builtins.readFile [
        ../config/theme/palette.nix
        ../config/theme/HelixGraphiteFern.colors
        ../config/theme/HelixGraphiteFern.colorscheme
        ../config/theme/HelixGraphiteFern.profile
        ../config/theme/wallpaper.svg
        ../config/theme/gtk-3.0-settings.ini
        ../config/theme/gtk-4.0-settings.ini
        ../config/theme/waybar.css
        ../config/theme/mako.conf
        ../config/theme/fuzzel.ini
        ../config/theme/steam.css
        ../scripts/apply-theme-settings.py
        ./theme.nix
      ]
    )
  );

  themePackage = pkgs.runCommand "helix-graphite-fern-theme" { } ''
    install -Dm444 ${themeDirectory}/HelixGraphiteFern.colors \
      $out/share/color-schemes/HelixGraphiteFern.colors
    install -Dm444 ${themeDirectory}/wallpaper.svg \
      $out/share/wallpapers/HelixGraphiteFern/contents/images/wallpaper.svg
    install -Dm444 ${themeDirectory}/HelixGraphiteFern.colorscheme \
      $out/share/konsole/HelixGraphiteFern.colorscheme
    install -Dm444 ${themeDirectory}/HelixGraphiteFern.profile \
      $out/share/konsole/HelixGraphiteFern.profile
  '';

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
    background=${wallpaper}
    needsFullUserModel=false
    EOF
  '';

  applyTheme = pkgs.writeShellApplication {
    name = "helix-apply-theme";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dconf
      pkgs.glib
      pkgs.kdePackages.kconfig
      pkgs.kdePackages.plasma-workspace
      pkgs.python3
    ];
    text = ''
      export HOME=${lib.escapeShellArg host.home}
      export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
      marker="$XDG_CONFIG_HOME/helix/theme-revision"
      revision=${lib.escapeShellArg themeRevision}
      force=0

      case ''${1:-} in
      "") ;;
      --force) force=1 ;;
      --help)
        printf 'Usage: helix-apply-theme [--force|--help]\n'
        exit 0
        ;;
      *)
        printf 'Usage: helix-apply-theme [--force|--help]\n' >&2
        exit 2
        ;;
      esac

      if [[ $force == 0 && -r $marker ]] && [[ $(<"$marker") == "$revision" ]]; then
        printf 'Helix Graphite + Fern is already current.\n'
        exit 0
      fi
      if [[ -z ''${DBUS_SESSION_BUS_ADDRESS:-} || -z ''${XDG_CURRENT_DESKTOP:-} ]]; then
        printf 'Helix Graphite + Fern requires an active graphical session and session D-Bus.\n' >&2
        exit 1
      fi

      python3 /etc/helix/theme/apply-theme-settings.py merge-ini \
        /etc/helix/theme/gtk-3.0-settings.ini "$XDG_CONFIG_HOME/gtk-3.0/settings.ini"
      python3 /etc/helix/theme/apply-theme-settings.py merge-ini \
        /etc/helix/theme/gtk-4.0-settings.ini "$XDG_CONFIG_HOME/gtk-4.0/settings.ini"
      python3 /etc/helix/theme/apply-theme-settings.py merge-vscode \
        "$XDG_CONFIG_HOME/Code/User/settings.json"

      gsettings set org.gnome.desktop.interface color-scheme prefer-dark
      gsettings set org.gnome.desktop.interface gtk-theme Breeze-Dark
      gsettings set org.gnome.desktop.interface icon-theme breeze-dark
      gsettings set io.github.Foldex.AdwSteamGtk prefs-install-custom-css true

      if [[ $XDG_CURRENT_DESKTOP == *KDE* ]]; then
        plasma-apply-desktoptheme breeze-dark
        kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop
        kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze
        kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-dark
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Breeze
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize Tiny
        kwriteconfig6 --file breezerc --group Common --key OutlineIntensity 35
        kwriteconfig6 --file breezerc --group Common --key ShadowStrength 180
        kwriteconfig6 --file plasmarc --group Theme --key name breeze-dark
        plasma-apply-cursortheme breeze_cursors
        plasma-apply-colorscheme HelixGraphiteFern
        plasma-apply-wallpaperimage ${lib.escapeShellArg wallpaper}
        kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile HelixGraphiteFern.profile
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper \
          --group org.kde.image --group General --key Image "file://${wallpaper}"
      fi

      install -Dm644 /dev/null "$marker"
      printf '%s\n' "$revision" > "$marker"
      printf 'Applied Helix Graphite + Fern revision %s. Restart applications if needed.\n' "$revision"
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
        printf 'Usage: helix-apply-steam-theme\n'
        printf 'Close Steam first. The command installs Adwaita-for-Steam with Graphite + Fern colours.\n'
        exit 0
      fi
      if [[ $# -ne 0 ]]; then
        printf 'Usage: helix-apply-steam-theme\n' >&2
        exit 2
      fi
      if pgrep -x steam >/dev/null || pgrep -x steamwebhelper >/dev/null; then
        printf 'Close Steam completely before applying its theme.\n' >&2
        exit 1
      fi

      export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
      install -Dm644 /etc/helix/theme/steam.css \
        "$XDG_CONFIG_HOME/AdwSteamGtk/custom.css"
      gsettings set io.github.Foldex.AdwSteamGtk prefs-install-custom-css true
      adwaita-steam-gtk --install --options \
        'color_theme:oled;rounded_corners:false;win_controls:windows;win_controls_layout:auto'
      printf 'Applied the Graphite + Fern Steam skin. Start Steam to inspect it.\n'
    '';
  };
in
{
  programs.dconf.enable = true;

  services.displayManager.sddm = {
    theme = "helix-graphite-fern";
  };

  environment.systemPackages = [
    themePackage
    pkgs.kdePackages.breeze-gtk
    pkgs.kdePackages.breeze-icons
    pkgs.kdePackages.kconfig
    applyTheme
    applySteamTheme
    sddmTheme
  ];

  environment.etc = {
    "helix/theme/gtk-3.0-settings.ini".source = ../config/theme/gtk-3.0-settings.ini;
    "helix/theme/gtk-4.0-settings.ini".source = ../config/theme/gtk-4.0-settings.ini;
    "helix/theme/waybar.css".source = ../config/theme/waybar.css;
    "helix/theme/mako.conf".source = ../config/theme/mako.conf;
    "helix/theme/fuzzel.ini".source = ../config/theme/fuzzel.ini;
    "helix/theme/steam.css".source = ../config/theme/steam.css;
    "helix/theme/wallpaper.svg".source = ../config/theme/wallpaper.svg;
    "helix/theme/apply-theme-settings.py".source = ../scripts/apply-theme-settings.py;
  };

  systemd.user.services.helix-graphite-fern-theme = {
    description = "Apply the Helix Graphite + Fern appearance policy for ${host.displayName}";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session-pre.target" ];
    unitConfig.ConditionUser = host.user;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${applyTheme}/bin/helix-apply-theme";
      Environment = [
        "HOME=${host.home}"
        "XDG_CONFIG_HOME=${host.home}/.config"
      ];
    };
  };
}
