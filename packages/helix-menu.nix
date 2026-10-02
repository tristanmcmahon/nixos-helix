# Fuzzel with the current Helix theme, for every chooser and prompt. Falls back
# to the Fern configuration before helix-theme has run.
{ pkgs }:

pkgs.writeShellApplication {
  name = "helix-menu";
  runtimeInputs = [ pkgs.fuzzel ];
  text = ''
    config="''${XDG_CONFIG_HOME:-$HOME/.config}/helix/theme/current/fuzzel.ini"
    [[ -r $config ]] || config=/etc/helix/theme/fuzzel.ini
    exec fuzzel --config "$config" "$@"
  '';
}
