{ lib, pkgs, ... }:

let
  helixMenu = import ../packages/helix-menu.nix { inherit pkgs; };
  helix = import ../config/helix.nix;
  managedConfig = ../config/ghostty/config.ghostty;
  palettes = import ../config/theme/palettes.nix;
  themeFamily = import ../packages/helix-theme-family.nix { inherit pkgs; };

  # One table drives the profile menu, the per-surface random choice, the
  # installed profile files and the generated colour sequences. Main is the
  # Fern rendering of the theme template, so it always matches the Helix
  # default; the others are hand-tuned files in config/ghostty/profiles.
  profiles = [
    {
      name = "main";
      label = "Main   · JetBrains Mono    · follows the Helix theme";
    }
    {
      name = "moss";
      label = "Moss   · Maple Mono        · softer green";
    }
    {
      name = "slate";
      label = "Slate  · Iosevka           · cool graphite";
    }
    {
      name = "ember";
      label = "Ember  · Monaspace Neon    · warm graphite";
    }
    {
      name = "tide";
      label = "Tide   · Monaspace Argon   · marine blue-teal";
    }
    {
      name = "dusk";
      label = "Dusk   · Monaspace Xenon   · muted violet";
    }
    {
      name = "sand";
      label = "Sand   · Monaspace Krypton · warm ochre";
    }
    {
      name = "frost";
      label = "Frost  · Monaspace Radon   · cold silver-blue";
    }
  ];
  profileNames = map (profile: profile.name) profiles;
  profileFile = name: ../config/ghostty/profiles + "/${name}.ghostty";
  mainProfileText =
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
  profileText =
    name: if name == "main" then mainProfileText else builtins.readFile (profileFile name);

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
    name: "${name})\n${surfaceEscapes (profileText name)};;"
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

  # Ghostty applies command to every surface after the first one: each new
  # split, tab or window gets a random profile's colours inside its own PTY,
  # which is compositor-neutral and needs no PID or timing heuristics. The
  # default profile (ghostty-profile) still decides the first surface and the
  # font.
  ghosttySurfaceShell = pkgs.writeShellApplication {
    name = "ghostty-surface-shell";
    runtimeInputs = [ ghosttySurfaceProfile ];
    text = ''
      profiles=(${lib.escapeShellArgs profileNames})
      ghostty-surface-profile "''${profiles[RANDOM % ''${#profiles[@]}]}"
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
      selection=$(printf '%s\n' ${lib.escapeShellArgs (map (profile: profile.label) profiles)} |
        helix-menu --dmenu --prompt='Ghostty profile: ' || true)
      profile=''${selection%% *}
      profile=''${profile,,}
      case $profile in
        ${lib.concatStringsSep "|" profileNames}) ;;
        *) profile= ;;
      esac
      [[ -n $profile ]] || exit 0

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

  # Recolour only the current split or tab: run inside it, with a profile name
  # or with no argument to choose from the menu. The default profile and font
  # are unchanged; that is ghostty-profile's job.
  ghosttyTheme = pkgs.writeShellApplication {
    name = "ghostty-theme";
    runtimeInputs = [
      helixMenu
      ghosttySurfaceProfile
    ];
    text = ''
      case ''${1:-} in
      --help | -h)
        printf 'Usage: ghostty-theme [%s]\n' ${lib.escapeShellArg (lib.concatStringsSep "|" profileNames)}
        printf 'Recolour the current Ghostty split or tab; no argument opens a menu.\n'
        exit 0
        ;;
      "")
        selection=$(printf '%s\n' ${lib.escapeShellArgs (map (profile: profile.label) profiles)} |
          helix-menu --dmenu --prompt='This surface: ' || true)
        profile=''${selection%% *}
        profile=''${profile,,}
        [[ -n $profile ]] || exit 0
        ;;
      *)
        profile=$1
        ;;
      esac
      case $profile in
        ${lib.concatStringsSep "|" profileNames}) ghostty-surface-profile "$profile" ;;
        *)
          printf 'Unknown Ghostty profile: %s\n' "$profile" >&2
          exit 2
          ;;
      esac
    '';
  };

  ghosttyProfileLauncher = pkgs.makeDesktopItem {
    name = "ghostty-profile";
    desktopName = "Ghostty Profile";
    comment = "Switch the Ghostty font and colour profile";
    exec = "${ghosttyProfile}/bin/ghostty-profile";
    icon = "com.mitchellh.ghostty";
    # One main category, so Plasma lists the launcher once.
    categories = [ "Utility" ];
    extraConfig = {
      "X-KDE-Shortcuts" = "Meta+Shift+Return";
    };
  };
in
{
  environment = {
    etc = {
      "helix/ghostty/config.ghostty".source = managedConfig;
    }
    // lib.listToAttrs (
      map (name: {
        name = "helix/ghostty/profiles/${name}.ghostty";
        value.source =
          if name == "main" then "${themeFamily}/generated/fern/ghostty.ghostty" else profileFile name;
      }) profileNames
    );

    systemPackages = [
      ghosttyProfile
      ghosttyProfileLauncher
      ghosttySurfaceProfile
      ghosttySurfaceShell
      ghosttyTheme
    ];
  };

  # Ghostty injects its Bash integration only into a shell it launches
  # directly, which is the first surface; later surfaces run
  # ghostty-surface-shell and would otherwise lose the ssh-env wrapper, sending
  # TERM=xterm-ghostty to hosts without that terminfo (Backspace and Delete
  # break on mister and Infernalnexus). Load it here for those shells, but
  # never twice: __ghostty_bash_flags exists while injection sources bashrc.
  programs.bash.interactiveShellInit = ''
    if [[ -n ''${GHOSTTY_RESOURCES_DIR:-} && -z ''${__ghostty_bash_flags+set} ]] &&
      ! declare -F __ghostty_precmd >/dev/null &&
      [[ -r $GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash ]]; then
      export GHOSTTY_SHELL_FEATURES=''${GHOSTTY_SHELL_FEATURES:-ssh-env}
      builtin source "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash"
    fi
  '';

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
