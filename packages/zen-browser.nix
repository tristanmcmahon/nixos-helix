{
  appimageTools,
  fetchurl,
  lib,
}:

let
  pname = "zen-browser";
  version = "1.21.10b";
  src = fetchurl {
    url = "https://github.com/zen-browser/desktop/releases/download/${version}/zen-x86_64.AppImage";
    hash = "sha256-T6aOSwBL+f4qxKtERnYcBirTxWZV6KWr3crVgqHlcoM=";
  };
  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 rec {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/zen.desktop \
      $out/share/applications/zen.desktop
    substituteInPlace $out/share/applications/zen.desktop \
      --replace-fail 'Exec=zen' 'Exec=${pname}'
    cp -r ${appimageContents}/usr/share/icons $out/share/
  '';

  meta = {
    description = "Firefox-based browser focused on privacy and customization";
    homepage = "https://zen-browser.app/";
    license = lib.licenses.mpl20;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
