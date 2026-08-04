# Media applications

Helix installs a desktop-only media consumption set. Spotify and VLC are the
mandatory baseline: Spotify is the normal native nixpkgs graphical client, and
VLC is the broad-compatibility troubleshooting player. mpv supplies a light
command-line playback engine while Haruna provides the Plasma-oriented graphical
mpv interface. Strawberry manages and plays a local music library.

Plex Desktop (`plex-desktop`) is the selected Plex playback client. It suits a
normal mouse-and-keyboard workstation better than the ten-foot `plex-htpc`
interface. This does not install the `plex` server package or any Plex service.

GridPlayer 0.5.4 is packaged natively from the pinned upstream GitHub tag with
`buildPythonApplication` and Poetry metadata. Its declared PyQt5, python-vlc,
Streamlink, and yt-dlp dependencies are retained, libVLC is available through
the wrapper, and Nix installs its executable, desktop entry, and upstream icon.
It provides the otherwise-missing configurable simultaneous-video grid.

Select libraries and files beneath `/mnt/infernalnexus/nas1` inside the
applications after activation. A native systemd automount keeps access on
demand without blocking boot. Applications use this stable local path, so a
future SMB-to-NFS transport change will not alter their saved paths. No media
server, downloader, or library automation runs on Helix, and no MIME defaults
are imposed yet.
