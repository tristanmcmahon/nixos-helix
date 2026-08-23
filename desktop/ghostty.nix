{ pkgs, ... }:

let
  managedConfig = ../config/ghostty/config.ghostty;
  profiles = {
    main = ../config/ghostty/profiles/main.ghostty;
    moss = ../config/ghostty/profiles/moss.ghostty;
    slate = ../config/ghostty/profiles/slate.ghostty;
    ember = ../config/ghostty/profiles/ember.ghostty;
  };

  ghosttySurfaceProfile = pkgs.writeShellApplication {
    name = "ghostty-surface-profile";
    text = ''
      profile=''${1:-}

      case "$profile" in
        main)
          printf '\033]10;#E4E8E5\033\\\033]11;#0B0D0C\033\\\033]12;#81C995\033\\'
          printf '\033]4;0;#0B0D0C;1;#D77A78;2;#67B87A;3;#D6AD63;4;#76A8B5;5;#A890B8;6;#72B6A1;7;#D6DCD8;8;#7E8981;9;#E29491;10;#81C995;11;#E2BF7E;12;#91BCC6;13;#BDA6C9;14;#8CCABA;15;#F1F4F2\033\\'
          ;;
        moss)
          printf '\033]10;#E0E7E2\033\\\033]11;#0D110E\033\\\033]12;#8FC79B\033\\'
          printf '\033]4;0;#0D110E;1;#D27C79;2;#72B77F;3;#CFAB6B;4;#7BA4AD;5;#A28FAE;6;#76AA98;7;#D1D9D3;8;#78867D;9;#E09490;10;#8FC79B;11;#DEBC81;12;#91B7BE;13;#B8A5C0;14;#8FC3B1;15;#EEF2EF\033\\'
          ;;
        slate)
          printf '\033]10;#E2E7E8\033\\\033]11;#0C0F11\033\\\033]12;#87B7C0\033\\'
          printf '\033]4;0;#0C0F11;1;#D47D7B;2;#70B58A;3;#D0AD6D;4;#79A9B6;5;#A18FAC;6;#72B0A6;7;#D5DDDE;8;#778286;9;#E19693;10;#86C29A;11;#DCBD82;12;#93BDC7;13;#B5A4BF;14;#8BC4BA;15;#F0F4F4\033\\'
          ;;
        ember)
          printf '\033]10;#E8E3DC\033\\\033]11;#100F0D\033\\\033]12;#D4B071\033\\'
          printf '\033]4;0;#100F0D;1;#D77F79;2;#78AF7F;3;#D4B071;4;#7F9FAC;5;#A491A5;6;#77A99A;7;#D9D3CB;8;#837D74;9;#E39992;10;#8CC18F;11;#E2C084;12;#96B4BE;13;#BAA5B7;14;#8EBCAF;15;#F3EFE9\033\\'
          ;;
        *)
          printf 'unknown Ghostty surface profile: %s\n' "$profile" >&2
          exit 2
          ;;
      esac
    '';
  };

  ghosttySplitProfile = pkgs.writeShellApplication {
    name = "ghostty-split-profile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fuzzel
      pkgs.gawk
      pkgs.hyprland
      pkgs.jq
      pkgs.procps
      ghosttySurfaceProfile
    ];
    text = ''
      # Hyprland invokes this from a non-consuming bind: the same keypress still
      # reaches Ghostty and creates the split using Ghostty's native action.
      active=$(hyprctl activewindow -j)
      class=$(jq -r '.class // ""' <<< "$active")
      case "$class" in
        com.mitchellh.ghostty | ghostty) ;;
        *) exit 0 ;;
      esac
      ghostty_pid=$(jq -r '.pid // empty' <<< "$active")
      [[ -n "$ghostty_pid" ]] || exit 0

      # Give Ghostty time to consume the non-consumed key event and start the
      # fresh shell before Fuzzel takes keyboard focus.
      sleep 0.10

      selection=$(printf '%s\n' \
        'Main  · graphite / fern' \
        'Moss  · softer green' \
        'Slate · cool graphite' \
        'Ember · warm graphite' |
        fuzzel --config /etc/helix/theme/fuzzel.ini --dmenu --prompt='New split: ')

      case "$selection" in
        Main*) profile=main ;;
        Moss*) profile=moss ;;
        Slate*) profile=slate ;;
        Ember*) profile=ember ;;
        *) exit 0 ;;
      esac

      # A Ghostty split is its own PTY-backed surface. The newest direct child
      # of the owning Ghostty process is the shell for the split just created.
      # Writing OSC colour controls to that PTY changes only that surface and
      # does not inject a command into shell history or disturb a running TUI.
      tty=$(ps --ppid "$ghostty_pid" -o tty= --sort=start_time |
        awk 'NF && $1 != "?" { tty=$1 } END { print tty }')
      [[ -n "$tty" ]] || exit 0

      ghostty-surface-profile "$profile" > "/dev/$tty"
    '';
  };

  ghosttyProfile = pkgs.writeShellApplication {
    name = "ghostty-profile";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.fuzzel
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      selection=$(printf '%s\n' \
        'Main   · JetBrains Mono · graphite / fern' \
        'Moss   · Maple Mono     · softer green' \
        'Slate  · Iosevka        · cool graphite' \
        'Ember  · Monaspace Neon · warm graphite' |
        fuzzel --config /etc/helix/theme/fuzzel.ini --dmenu --prompt='Ghostty profile: ')

      case "$selection" in
        Main*) profile=main ;;
        Moss*) profile=moss ;;
        Slate*) profile=slate ;;
        Ember*) profile=ember ;;
        *) exit 0 ;;
      esac

      install -m 0644 "/etc/helix/ghostty/profiles/$profile.ghostty" \
        "$HOME/.config/ghostty/profile.ghostty"

      # Ghostty's GTK build reloads configuration on SIGUSR2. Prefer the
      # systemd-owned process when available, with a direct signal fallback.
      systemctl --user reload app-com.mitchellh.ghostty.service 2>/dev/null ||
        pkill -USR2 -x ghostty 2>/dev/null || true
    '';
  };
in
{
  environment = {
    etc = {
      "helix/ghostty/config.ghostty".source = managedConfig;
      "helix/ghostty/profiles/main.ghostty".source = profiles.main;
      "helix/ghostty/profiles/moss.ghostty".source = profiles.moss;
      "helix/ghostty/profiles/slate.ghostty".source = profiles.slate;
      "helix/ghostty/profiles/ember.ghostty".source = profiles.ember;
    };

    systemPackages = [
      ghosttyProfile
      ghosttySplitProfile
      ghosttySurfaceProfile
    ];
  };

  # Deploy the repository-owned baseline as a regular file. The selected
  # appearance profile is writable state and is only initialised to Main once,
  # so rebuilding the system does not reset the user's current choice.
  systemd.user.services.helix-ghostty-config = {
    description = "Deploy the Helix Ghostty configuration";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "tristan";
    serviceConfig = {
      Type = "oneshot";
      Environment = [
        "HOME=/home/tristan"
        "XDG_CONFIG_HOME=/home/tristan/.config"
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
