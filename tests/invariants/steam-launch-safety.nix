context:
let
  inherit (context) config lib;
  steamArgs = config.programs.steam.package.passthru.args;
  inherit (steamArgs) profile;
  bwrapArgsText = lib.concatStringsSep "\n" steamArgs.extraBwrapArgs;
in
assert config.programs.steam.enable;
# Keep the user-visible, previously qualified Vulkan benchmark configuration.
assert lib.hasInfix "MANGOHUD=1" profile;
assert lib.hasInfix "MANGOHUD_CONFIG=" profile;
assert lib.hasInfix "helix/game-benchmarks" profile;
# The 2026-11-27 incident proved that intercepting game launches to gain
# optional OpenGL logging can prevent games from showing a window.
# Fail closed on the exact interception mechanisms that caused it.
assert !(lib.hasInfix "LD_PRELOAD=" profile);
assert !(lib.hasInfix "LD_LIBRARY_PATH=" profile);
assert !(lib.hasInfix "STEAM_GAME_LAUNCH_SHELL=" profile);
assert !(lib.hasInfix "MANGOHUD_DLSYM=" profile);
assert !(lib.hasInfix "--setenv LD_PRELOAD" bwrapArgsText);
assert !(lib.hasInfix "--setenv LD_LIBRARY_PATH" bwrapArgsText);
assert !(lib.hasInfix "--setenv XDG_DATA_DIRS" bwrapArgsText);
true
