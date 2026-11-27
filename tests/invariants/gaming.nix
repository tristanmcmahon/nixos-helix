context:
let
  inherit (context) config lib;
  steamArgs = config.programs.steam.package.passthru.args;
  bwrapArgsText = lib.concatStringsSep "\n" steamArgs.extraBwrapArgs;
  hasSetenv =
    name: value: lib.hasInfix "--setenv ${name} " bwrapArgsText && lib.hasInfix value bwrapArgsText;
in
assert config.programs.steam.enable;
# extraEnv has no attribute of its own on passthru.args: the steam package
# wrapper strips it before calling buildFHSEnv and folds its content into
# the generated `profile` string instead (`set -a; <extraEnv>; set +a`).
assert lib.hasInfix "MANGOHUD=1" steamArgs.profile;
assert lib.hasInfix "helix/game-benchmarks" steamArgs.profile;
# The OpenGL MangoHud shim must be injected at the bwrap exec boundary, not
# via extraProfile: extraProfile renders into the exact same generated FHS
# profile script as extraEnv (steam package.nix: both land in a single
# `set -a; <extraEnv>; set +a; <extraProfile>` block), so something
# downstream (Steam's own steam.sh, or the compiled client's per-game
# sandbox construction) discards LD_PRELOAD/LD_LIBRARY_PATH from that path
# before any game launches — confirmed on real Helix hardware: MANGOHUD=1
# survives into the game process every time, a prior extraProfile-based
# LD_PRELOAD export never did. extraBwrapArgs sets these directly on
# bubblewrap's container-init process instead, ambient from the first
# process in the sandbox, with no shell-profile step to skip.
assert hasSetenv "LD_PRELOAD" "libMangoHud_shim.so";
assert hasSetenv "LD_LIBRARY_PATH" "lib/mangohud";
assert hasSetenv "XDG_DATA_DIRS" "mangohud";
# Absolute store paths only: a bare "libMangoHud_shim.so" filename depends on
# LD_LIBRARY_PATH resolution order surviving every sandbox boundary, which is
# exactly the fragility this mechanism was chosen to avoid.
assert lib.hasInfix "/nix/store" bwrapArgsText;
# Lock in that the fix removed the dead extraProfile-based LD_PRELOAD
# export rather than leaving both mechanisms in place.
assert !(lib.hasInfix "LD_PRELOAD" steamArgs.profile);
true
