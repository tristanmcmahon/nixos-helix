{ lib, pkgs, ... }:

let
  helixMenu = import ../packages/helix-menu.nix { inherit pkgs; };
  helix = import ../config/helix.nix;
  managedConfig = ../config/ghostty/config.ghostty;
  palettes = import ../config/theme/palettes.nix;
  themeFamily = import ../packages/helix-theme-family.nix { inherit pkgs; };

  # Main is the Fern rendering of the theme template, so it always matches the
  # Helix default; Moss, Slate and Ember are hand-tuned profiles.
  profileSources = {
    main =
      let
        fern = palettes.themes.fern;
        roles = builtins.attrNames (
          removeAttrs fern [
            "name"
            "description"
            "random"
          ]
        );
      in
      lib.replaceStrings (map (role: "@${role}@") roles) (map (role: fern.${role}) roles) (
        builtins.readFile ../config/theme/templates/ghostty.ghostty
      );
    moss = builtins.readFile ../config/ghostty/profiles/moss.ghostty;
    slate = builtins.readFile ../config/ghostty/profiles/slate.ghostty;
    ember = builtins.readFile ../config/ghostty/profiles/ember.ghostty;
  };
  profileNames = [
    "main"
    "moss"
    "slate"
    "ember"
  ];

  # The OSC 10/11/12 (foreground, background, cursor) and OSC 4 (palette)
  # sequences that recolour one surface, derived from a profile's own values.
  surfaceEscapes =
    text:
    let
      lines = lib.splitString "\n" text;
      value =
        key:
        lib.head (
          lib.concatMap (
            line:
            let
              match = builtins.match "${key} = (#[0-9A-Fa-f]{6})" line;
            in
            lib.optional (match != null) (lib.head match)
          ) lines
        );
      palette = lib.concatMap (
        line:
        let
          match = builtins.match "palette = ([0-9]+)=(#[0-9A-Fa-f]{6})" line;
        in
        lib.optional (match != null) "${lib.elemAt match 0};${lib.elemAt match 1}"
      ) lines;
    in
    ''
      printf '\033]10;${value "foreground"}\033\\\033]11;${value "background"}\033\\\033]12;${value "cursor-color"}\033\\'
      printf '\033]4;${lib.concatStringsSep ";" palette}\033\\'
    '';
  surfaceCases = lib.concatMapStringsSep "\n" (
    name: "${name})\n${surfaceEscapes profileSources.${name}};;"
  ) profileNames;

  ghosttySurfaceProfile = pkgs.writeShellApplication {
    name = "ghostty-surface-profile";
    excludeShellChecks = [ "SC1003" ];
    text = ''
      profile=''${1:-}

      case "$profile" in
        ${surfaceCases}
        *)
          printf 'unknown Ghostty surface profile: %s\n' "$profile" >&2
          exit 2
          ;;
      esac
    '';
  };

  # Ghostty applies command to every surface after the first one. Running the
  # chooser inside that fresh PTY makes per-surface colours compositor-neutral
  # and avoids compositor-specific PID or timing heuristics.
  ghosttySurfaceShell = pkgs.writeShellApplication {
    name = "ghostty-surface-shell";
    runtimeInputs = [
      helixMenu
      ghosttySurfaceProfile
    ];
    text = ''
      selection=$(printf '%s\n' \
        'Main  · graphite / fern' \
        'Moss  · softer green' \
        'Slate · cool graphite' \
        'Ember · warm graphite' |
        helix-menu --dmenu --prompt='New Ghostty surface: ' || true)

      case "$selection" in
        Main*) profile=main ;;
        Moss*) profile=moss ;;
        Slate*) profile=slate ;;
        Ember*) profile=ember ;;
        *) profile= ;;
      esac

      if [[ -n "$profile" ]]; then
        ghostty-surface-profile "$profile"
      fi

      exec ${pkgs.bashInteractive}/bin/bash
    '';
  };

  ghosttyProfile = pkgs.writeShellApplication {
    name = "ghostty-profile";
    runtimeInputs = [
      pkgs.coreutils
      helixMenu
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      selection=$(printf '%s\n' \
        'Main   · JetBrains Mono · follows the Helix theme' \
        'Moss   · Maple Mono     · softer green' \
        'Slate  · Iosevka        · cool graphite' \
        'Ember  · Monaspace Neon · warm graphite' |
        helix-menu --dmenu --prompt='Ghostty profile: ' || true)

      case "$selection" in
        Main*) profile=main ;;
        Moss*) profile=moss ;;
        Slate*) profile=slate ;;
        Ember*) profile=ember ;;
        *) exit 0 ;;
      esac

      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
      mkdir -p "$config_dir"
      source_profile=/etc/helix/ghostty/profiles/$profile.ghostty
      # Main follows the current Helix theme; helix-theme keeps it in step.
      current_theme_profile="''${XDG_CONFIG_HOME:-$HOME/.config}/helix/theme/current/ghostty.ghostty"
      if [[ $profile == main && -r $current_theme_profile ]]; then
        source_profile=$current_theme_profile
      fi
      install -m 0644 "$source_profile" "$config_dir/profile.ghostty"
      printf '%s\n' "$profile" > "$config_dir/profile-name"

      # Ghostty's GTK build reloads configuration on SIGUSR2. Prefer the
      # systemd-owned process when available, with a direct signal fallback.
      systemctl --user reload app-com.mitchellh.ghostty.service 2>/dev/null ||
        pkill -USR2 -x ghostty 2>/dev/null || true
    '';
  };

  ghosttyProfileLauncher = pkgs.makeDesktopItem {
    name = "ghostty-profile";
    desktopName = "Ghostty Profile";
    comment = "Switch the Ghostty font and colour profile";
    exec = "${ghosttyProfile}/bin/ghostty-profile";
    icon = "com.mitchellh.ghostty";
    categories = [
      "System"
      "Utility"
    ];
    extraConfig = {
      "X-KDE-Shortcuts" = "Meta+Shift+Return";
    };
  };
in
{
  environment = {
    etc = {
      "helix/ghostty/config.ghostty".source = managedConfig;
      "helix/ghostty/profiles/main.ghostty".source = "${themeFamily}/generated/fern/ghostty.ghostty";
      "helix/ghostty/profiles/moss.ghostty".source = ../config/ghostty/profiles/moss.ghostty;
      "helix/ghostty/profiles/slate.ghostty".source = ../config/ghostty/profiles/slate.ghostty;
      "helix/ghostty/profiles/ember.ghostty".source = ../config/ghostty/profiles/ember.ghostty;
    };

    systemPackages = [
      ghosttyProfile
      ghosttyProfileLauncher
      ghosttySurfaceProfile
      ghosttySurfaceShell
    ];
  };

  # Deploy the repository-owned baseline as a regular file. The selected
  # appearance profile is writable state and is only initialised to Main once,
  # so rebuilding the system does not reset the user's current choice.
  systemd.user.services.helix-ghostty-config = {
    description = "Deploy the Helix Ghostty configuration";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = helix.user;
    serviceConfig = {
      Type = "oneshot";
      Environment = [
        "HOME=${helix.home}"
        "XDG_CONFIG_HOME=${helix.configHome}"
      ];
    };
    script = ''
      destination="$XDG_CONFIG_HOME/ghostty/config.ghostty"
      profile="$XDG_CONFIG_HOME/ghostty/profile.ghostty"
      source=/etc/helix/ghostty/config.ghostty

      ${pkgs.coreutils}/bin/mkdir -p "$XDG_CONFIG_HOME/ghostty"
      if [[ -e "$destination" ]] && ! ${pkgs.diffutils}/bin/cmp -s "$source" "$destination"; then
        if [[ ! -e "$destination.pre-nixos" ]]; then
          ${pkgs.coreutils}/bin/cp -p "$destination" "$destination.pre-nixos"
        fi
      fi

      ${pkgs.coreutils}/bin/install -m 0644 "$source" "$destination"

      if [[ ! -e "$profile" ]]; then
        ${pkgs.coreutils}/bin/install -m 0644 \
          /etc/helix/ghostty/profiles/main.ghostty "$profile"
      fi
    '';
  };
}
