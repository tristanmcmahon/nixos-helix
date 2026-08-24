{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  xdg-utils,
  alsa-lib,
  at-spi2-atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  kdePackages,
  libdrm,
  libgbm,
  libxkbcommon,
  libusb1,
  nspr,
  nss,
  pango,
  systemd,
  xorg,
}:

stdenv.mkDerivation {
  pname = "chatgpt";
  version = "26.818.61809";

  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb";
    hash = "sha256-G7piptvS1Jl1xihQ2O3arWBdoZNVexlJgiJeVrGUGJE=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    kdePackages.qtbase
    libdrm
    libgbm
    libxkbcommon
    libusb1
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    systemd
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
  ];

  dontConfigure = true;
  dontBuild = true;
  dontWrapQtApps = true;

  # The Debian package includes both desktop-integration shims. Helix uses
  # Plasma 6, so patch the Qt 6 shim and leave the unused Qt 5 shim optional.
  autoPatchelfIgnoreMissingDeps = [
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libc.musl-x86_64.so.1"
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/lib" "$out/share"
    cp -r source/usr/lib/chatgpt "$out/lib/chatgpt"
    cp -r source/usr/share/applications source/usr/share/pixmaps "$out/share/"

    makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}

    runHook postInstall
  '';

  postFixup = ''
    substituteInPlace "$out/share/applications/chatgpt.desktop" \
      --replace-fail "Exec=chatgpt %U" "Exec=$out/bin/chatgpt %U"
  '';

  meta = {
    description = "Official ChatGPT desktop application";
    homepage = "https://chatgpt.com/";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
