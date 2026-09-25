# Snapshot of hamCade dependencies.nix from private repo commit
# b64dc3c90c66b46c8e4e35ba5f590706ece8d8f1.
#
# nixos-helix owns this small integration snapshot so evaluation and CI do not
# depend on a sibling private checkout. The hamCade application itself remains
# owned by ~/Projects/hamCade and is executed from there at runtime.
{
  pkgs ? import <nixpkgs> { },
}:
let
  arcadePkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/e1dc3132ff275f54cbde82f4dd52025a5944f37b.tar.gz";
    sha256 = "11f1j127mp4s79599hq2lax0p9083bg7fzyvgq62rdriw5ryhlvm";
  }) { };
  frontendSource = pkgs.fetchurl {
    url = "https://gitlab.com/es-de/emulationstation-de/-/package_files/288156961/download";
    sha256 = "3c61a44d738d55163daa58ede70720b425a0df62460c04dc23dd3ca586723581";
  };
in
{
  core = arcadePkgs.libretro.mame;
  auditMame = arcadePkgs.mame;
  retroarch = pkgs.retroarch-bare;
  shaders = pkgs.libretro-shaders-slang;
  controllers = pkgs.retroarch-joypad-autoconfig;
  sevenzip = pkgs.p7zip;
  chdtools = pkgs.mame.tools;
  theme = pkgs.appimageTools.extractType2 {
    pname = "hamcade-es-de";
    version = "3.4.1";
    src = frontendSource;
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
}
