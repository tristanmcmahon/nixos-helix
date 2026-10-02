# Renders every Helix theme from config/theme/palettes.nix and the templates
# in config/theme/templates. Shared by desktop/theme.nix and desktop/ghostty.nix.
{ pkgs }:

let
  palettes = import ../config/theme/palettes.nix;
  palettesJson = pkgs.writeText "helix-palettes.json" (builtins.toJSON palettes);
in
pkgs.runCommand "helix-theme-family" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${../scripts/generate-theme-family.py} ${palettesJson} ${../config/theme} $out/generated
  for theme in ${builtins.concatStringsSep " " palettes.order}; do
    colors=$(find "$out/generated/$theme" -maxdepth 1 -name '*.colors')
    scheme_name=$(basename "$colors" .colors)
    install -Dm444 "$colors" "$out/share/color-schemes/$scheme_name.colors"
    install -Dm444 "$out/generated/$theme/$scheme_name.colorscheme" "$out/share/konsole/$scheme_name.colorscheme"
    install -Dm444 "$out/generated/$theme/$scheme_name.profile" "$out/share/konsole/$scheme_name.profile"
    install -Dm444 "$out/generated/$theme/wallpaper.svg" \
      "$out/share/wallpapers/$scheme_name/contents/images/wallpaper.svg"
  done
''
