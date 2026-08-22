{ pkgs, ... }:

let
  managedConfig = ../config/ghostty/config.ghostty;
  profiles = {
    main = ../config/ghostty/profiles/main.ghostty;
    moss = ../config/ghostty/profiles/moss.ghostty;
    slate = ../config/ghostty/profiles/slate.ghostty;
    ember = ../config/ghostty/profiles/ember.ghostty;
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
  environment.etc."helix/ghostty/config.ghostty".source = managedConfig;
  environment.etc."helix/ghostty/profiles/main.ghostty".source = profiles.main;
  environment.etc."helix/ghostty/profiles/moss.ghostty".source = profiles.moss;
  environment.etc."helix/ghostty/profiles/slate.ghostty".source = profiles.slate;
  environment.etc."helix/ghostty/profiles/ember.ghostty".source = profiles.ember;

  environment.systemPackages = [ ghosttyProfile ];

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
