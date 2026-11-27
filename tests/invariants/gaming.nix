context:
let
  inherit (context) config lib;
  steamArgs = config.programs.steam.package.passthru.args;
  profile = steamArgs.profile;
  bwrapArgsText = lib.concatStringsSep "\n" steamArgs.extraBwrapArgs;
in
assert config.programs.steam.enable;
assert lib.hasInfix "MANGOHUD=1" profile;
assert lib.hasInfix "MANGOHUD_CONFIG=" profile;
assert lib.hasInfix "helix/game-benchmarks" profile;
# Games must acquire the GL shim at Steam's per-game shell boundary.
assert lib.hasInfix "STEAM_GAME_LAUNCH_SHELL=" profile;
assert lib.hasInfix "helix-steam-game-shell" profile;
# Never preload MangoHud globally into Steam's own FHS sandbox: that would
# affect Steam itself and replace runtime paths required by pressure-vessel.
assert !(lib.hasInfix "LD_PRELOAD=" profile);
assert !(lib.hasInfix "LD_LIBRARY_PATH=" profile);
assert !(lib.hasInfix "--setenv LD_PRELOAD" bwrapArgsText);
assert !(lib.hasInfix "--setenv LD_LIBRARY_PATH" bwrapArgsText);
assert !(lib.hasInfix "--setenv XDG_DATA_DIRS" bwrapArgsText);
true
