{ pkgs, ... }:

let
  managedConfig = ../config/ghostty/config.ghostty;
in
{
  environment.etc."helix/ghostty/config.ghostty".source = managedConfig;

  # Deploy a regular file rather than a misleading, immutable store symlink.
  # The first differing unmanaged file is retained once as config.ghostty.pre-nixos.
  systemd.user.services.helix-ghostty-config = {
    description = "Deploy the Helix Ghostty configuration";
    wantedBy = [ "default.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      destination="$HOME/.config/ghostty/config.ghostty"
      source=/etc/helix/ghostty/config.ghostty
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.config/ghostty"
      if [[ -e "$destination" ]] && ! ${pkgs.diffutils}/bin/cmp -s "$source" "$destination"; then
        if [[ ! -e "$destination.pre-nixos" ]]; then
          ${pkgs.coreutils}/bin/cp -p "$destination" "$destination.pre-nixos"
        fi
      fi
      ${pkgs.coreutils}/bin/install -m 0644 "$source" "$destination"
    '';
  };
}
