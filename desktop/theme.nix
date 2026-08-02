{
  config,
  lib,
  pkgs,
  ...
}:

let
  themeDirectory = ../config/theme;
  wallpaper = "${themePackage}/share/wallpapers/HelixAbyss/contents/images/wallpaper.svg";
  themeRevision = builtins.hashString "sha256" (
    builtins.concatStringsSep "" (
      map builtins.readFile [
        ../config/theme/HelixAbyss.colors
        ../config/theme/wallpaper.svg
        ../config/theme/gtk-3.0-settings.ini
        ../config/theme/gtk-4.0-settings.ini
        ../scripts/apply-theme-settings.py
      ]
    )
  );

  themePackage = pkgs.runCommand "helix-abyss-theme" { } ''
    install -Dm444 ${themeDirectory}/HelixAbyss.colors \
      $out/share/color-schemes/HelixAbyss.colors
    install -Dm444 ${themeDirectory}/wallpaper.svg \
      $out/share/wallpapers/HelixAbyss/contents/images/wallpaper.svg
  '';

  sddmTheme = pkgs.runCommand "sddm-theme-helix-abyss" { } ''
    mkdir -p $out/share/sddm/themes/helix-abyss
    cp -r ${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze/. \
      $out/share/sddm/themes/helix-abyss/
    chmod -R u+w $out/share/sddm/themes/helix-abyss
    cat > $out/share/sddm/themes/helix-abyss/theme.conf <<EOF
    [General]
    showlogo=hidden
    showClock=true
    type=image
    color=#080A0D
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
      pkgs.kdePackages.kconfig
      pkgs.kdePackages.plasma-workspace
      pkgs.python3
    ];
    text = ''
      export HOME=/home/tristan
      export XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}"
      marker="$XDG_CONFIG_HOME/helix/theme-revision"
      revision=${lib.escapeShellArg themeRevision}

      if [[ -r $marker ]] && [[ $(<"$marker") == "$revision" ]]; then
        exit 0
      fi
      if [[ -z ''${DBUS_SESSION_BUS_ADDRESS:-} || -z ''${XDG_CURRENT_DESKTOP:-} ]]; then
        printf 'Helix Abyss requires an active graphical session and session D-Bus.\n' >&2
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

      if [[ $XDG_CURRENT_DESKTOP == *KDE* ]]; then
        plasma-apply-colorscheme HelixAbyss
        plasma-apply-desktoptheme breeze-dark
        plasma-apply-cursortheme breeze_cursors
        plasma-apply-wallpaperimage ${lib.escapeShellArg wallpaper}
        kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop
        kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze
        kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-dark
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze
        kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Breeze
        kwriteconfig6 --file plasmarc --group Theme --key name breeze-dark
        kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper \
          --group org.kde.image --group General --key Image "file://${wallpaper}"
      fi

      install -Dm644 /dev/null "$marker"
      printf '%s\n' "$revision" > "$marker"
    '';
  };
in
{
  programs.dconf.enable = true;

  services.displayManager.sddm = {
    theme = "helix-abyss";
  };

  environment.systemPackages = [
    themePackage
    pkgs.kdePackages.breeze-gtk
    pkgs.kdePackages.breeze-icons
    pkgs.kdePackages.kconfig
    applyTheme
    sddmTheme
  ];

  environment.etc = {
    "helix/theme/gtk-3.0-settings.ini".source = ../config/theme/gtk-3.0-settings.ini;
    "helix/theme/gtk-4.0-settings.ini".source = ../config/theme/gtk-4.0-settings.ini;
    "helix/theme/waybar.css".source = ../config/theme/waybar.css;
    "helix/theme/mako.conf".source = ../config/theme/mako.conf;
    "helix/theme/fuzzel.ini".source = ../config/theme/fuzzel.ini;
    "helix/theme/wallpaper.svg".source = ../config/theme/wallpaper.svg;
    "helix/theme/apply-theme-settings.py".source = ../scripts/apply-theme-settings.py;
  };

  systemd.user.services.helix-abyss-theme = {
    description = "Apply the Helix Abyss appearance policy for Tristan";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session-pre.target" ];
    unitConfig.ConditionUser = "tristan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${applyTheme}/bin/helix-apply-theme";
      Environment = [
        "HOME=/home/tristan"
        "XDG_CONFIG_HOME=/home/tristan/.config"
      ];
    };
  };
}
