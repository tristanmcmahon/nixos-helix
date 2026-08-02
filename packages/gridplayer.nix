{
  fetchFromGitHub,
  lib,
  makeDesktopItem,
  python3Packages,
  streamlink,
  vlc,
}:

let
  desktopItem = makeDesktopItem {
    name = "gridplayer";
    desktopName = "GridPlayer";
    comment = "Play multiple videos side by side";
    exec = "gridplayer %F";
    icon = "gridplayer";
    categories = [
      "AudioVideo"
      "Player"
    ];
    mimeTypes = [
      "video/mp4"
      "video/x-matroska"
      "video/webm"
    ];
  };
in
python3Packages.buildPythonApplication rec {
  pname = "gridplayer";
  version = "0.5.4";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "vzhd1701";
    repo = "gridplayer";
    rev = "v${version}";
    hash = "sha256-kAA3O7I+uPO3nJ1x4KANrUlKv6iJWRu4VC8NpgWsTww=";
  };

  build-system = [ python3Packages.poetry-core ];

  dependencies = [
    python3Packages.pydantic
    python3Packages.pyqt5
    python3Packages.python-vlc
    python3Packages.yt-dlp
    streamlink
  ];

  nativeBuildInputs = [ python3Packages.pythonRelaxDepsHook ];
  pythonRelaxDeps = [
    "pyqt5"
    "python-vlc"
    "streamlink"
    "yt-dlp"
  ];

  postInstall = ''
    install -Dm444 resources/public/logo.svg \
      $out/share/icons/hicolor/scalable/apps/gridplayer.svg
    install -Dm444 ${desktopItem}/share/applications/gridplayer.desktop \
      $out/share/applications/gridplayer.desktop
  '';

  preFixup = ''
    wrapProgram $out/bin/gridplayer \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vlc ]}
  '';

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];
  pythonImportsCheck = [ "gridplayer" ];

  meta = {
    description = "VLC-based player for simultaneous videos in a configurable grid";
    homepage = "https://github.com/vzhd1701/gridplayer";
    changelog = "https://github.com/vzhd1701/gridplayer/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.gpl3Plus;
    mainProgram = "gridplayer";
    platforms = lib.platforms.linux;
  };
}
