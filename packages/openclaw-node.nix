{
  lib,
  nodejs_22,
  nodejs-slim_22,
  sqlite,
}:

let
  # NixOS 26.05 links Node 22 against the shared nixpkgs SQLite, and SQLite
  # before 3.51.3 has the WAL-reset corruption bug that OpenClaw rejects. Only
  # while both hold, build Node with its bundled SQLite instead. Once nixpkgs
  # ships a fixed SQLite (or stops sharing it), this falls back to the cached
  # nodejs_22 automatically and the source build of Node disappears.
  # scripts/nixpkgs-version-summary.sh evaluates this file too, so a bump pull
  # request says whether that build happens.
  minimumSqlite = "3.51.3";
  isSharedSqliteFlag = flag: lib.hasPrefix "--shared-sqlite" flag;
  needsBundledSqlite =
    builtins.any isSharedSqliteFlag nodejs-slim_22.configureFlags
    && lib.versionOlder sqlite.version minimumSqlite;
  node =
    if needsBundledSqlite then
      nodejs_22.override {
        nodejs-slim = nodejs-slim_22.overrideAttrs (old: {
          configureFlags = builtins.filter (flag: !(isSharedSqliteFlag flag)) old.configureFlags;
          # Node's own test suite (thousands of tests) re-verifies upstream
          # Node, not this one linkage change, and lengthens a build that no
          # binary cache provides. The gateway's install check covers what the
          # change is for.
          doCheck = false;
        });
      }
    else
      nodejs_22;
in
{
  inherit node minimumSqlite;
  fromSource = needsBundledSqlite;
}
