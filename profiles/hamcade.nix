{ pkgs, ... }:

let
  # hamCade remains a separately developed mutable checkout. Helix owns the
  # NixOS integration so evaluating this repository never depends on a sibling
  # checkout being present.
  hamCadeRepository = "/home/tristan/Projects/hamCade";

  # Keep the arcade core/audit pair on hamCade's reviewed MAME-compatible
  # Nixpkgs revision rather than silently following the workstation channel.
  arcadePkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/e1dc3132ff275f54cbde82f4dd52025a5944f37b.tar.gz";
    sha256 = "11f1j127mp4s79599hq2lax0p9083bg7fzyvgq62rdriw5ryhlvm";
  }) { };

  frontendSource = pkgs.fetchurl {
    url = "https://gitlab.com/es-de/emulationstation-de/-/package_files/288156961/download";
    sha256 = "3c61a44d738d55163daa58ede70720b425a0df62460c04dc23dd3ca586723581";
  };

  frontend = pkgs.appimageTools.wrapType2 {
    pname = "hamcade-es-de";
    version = "3.4.1";
    src = frontendSource;
    extraPkgs = p: [
      p.libxkbcommon
      p.libGL
    ];
  };

  launcher = pkgs.writeShellApplication {
    name = "hamcade";
    runtimeInputs = [
      pkgs.python3
      pkgs.bubblewrap
      pkgs.util-linux
      pkgs.curl
      pkgs.kdePackages.kdialog
    ];
    text = ''
      entrypoint=${hamCadeRepository}/hamcade.py
      if [[ ! -r $entrypoint ]]; then
        printf 'hamCade checkout is unavailable at %s\n' ${hamCadeRepository} >&2
        exit 1
      fi
      exec python3 "$entrypoint" "$@"
    '';
  };
in
{
  environment.systemPackages = [
    launcher
    frontend
    arcadePkgs.libretro.mame
    arcadePkgs.mame
    pkgs.retroarch-bare
    pkgs.libretro-shaders-slang
    pkgs.retroarch-joypad-autoconfig
    pkgs.p7zip
    pkgs.mame.tools
    (pkgs.makeDesktopItem {
      name = "hamcade";
      desktopName = "hamCade";
      comment = "Arcade games from your read-only NAS library";
      exec = "hamcade launch";
      icon = "applications-games";
      categories = [ "Game" ];
    })
  ];
}
