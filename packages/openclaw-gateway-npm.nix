{
  lib,
  stdenv,
  buildNpmPackage,
  callPackage,
  makeWrapper,
  sourceInfo,
  bundledAcpx,
  upstreamSource,
}:

let
  openclaw = callPackage ./openclaw-node.nix { };
  openclawNode = openclaw.node;
  inherit (openclaw) minimumSqlite;
  buildNpmPackageForOpenClaw = buildNpmPackage.override {
    nodejs = openclawNode;
  };
  wrapperSrc = upstreamSource + "/nix/npm/openclaw";
  lock = builtins.fromJSON (builtins.readFile (wrapperSrc + "/package-lock.json"));
  lockedVersion = lock.packages."node_modules/openclaw".version or null;
in

assert lib.assertMsg (lockedVersion == sourceInfo.releaseVersion)
  "OpenClaw npm lock version ${toString lockedVersion} does not match OpenClaw ${sourceInfo.releaseVersion}";
assert lib.assertMsg (
  (bundledAcpx.openclawRuntimePlugin.id or null) == "acpx"
) "bundledAcpx must be the generated ACPX runtime plugin package";
assert lib.assertMsg
  ((bundledAcpx.openclawRuntimePlugin.version or null) == sourceInfo.runtimePluginVersion)
  "ACPX runtime plugin version ${
    toString (bundledAcpx.openclawRuntimePlugin.version or null)
  } does not match OpenClaw runtime plugins ${sourceInfo.runtimePluginVersion}";

buildNpmPackageForOpenClaw {
  pname = "openclaw-gateway";
  version = sourceInfo.releaseVersion;

  src = wrapperSrc;
  npmDepsHash = sourceInfo.gatewayNpmDepsHash;
  dontNpmBuild = true;
  makeCacheWritable = true;

  npmInstallFlags = [
    "--omit=dev"
    "--ignore-scripts"
    "--legacy-peer-deps"
  ];

  nativeBuildInputs = [ makeWrapper ];

  env = {
    NODE_BIN = "${openclawNode}/bin/node";
    OPENCLAW_BUNDLED_ACPX = "${bundledAcpx}";
    OPENCLAW_NPM_PACKAGE_ROOT = "node_modules/openclaw";
    OPENCLAW_PATCH_NPM_DIST_SCRIPT = toString (
      upstreamSource + "/nix/scripts/patch-openclaw-npm-dist.mjs"
    );
    STDENV_SETUP = "${stdenv}/setup";
  };

  installPhase = toString (upstreamSource + "/nix/scripts/openclaw-gateway-npm-install.sh");

  # The reason for any Node override: fail the build, not the gateway at
  # runtime, if OpenClaw's Node links a SQLite with the WAL-reset bug.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${openclawNode}/bin/node --eval '
      const { DatabaseSync } = require("node:sqlite");
      const { v } = new DatabaseSync(":memory:").prepare("select sqlite_version() as v").get();
      // Compare part by part, missing parts as zero, like lib.versionOlder;
      // an unparseable version fails rather than passes.
      const have = v.split(".").map(Number);
      const need = "${minimumSqlite}".split(".").map(Number);
      let newEnough = have.every(Number.isInteger);
      for (let i = 0; newEnough && i < Math.max(have.length, need.length); i++) {
        if ((have[i] ?? 0) !== (need[i] ?? 0)) {
          newEnough = (have[i] ?? 0) > (need[i] ?? 0);
          break;
        }
      }
      if (!newEnough) {
        console.error(`OpenClaw Node links SQLite ''${v}; ${minimumSqlite} or newer is required`);
        process.exit(1);
      }
    '
    runHook postInstallCheck
  '';

  dontFixup = true;
  dontStrip = true;
  dontPatchShebangs = true;

  passthru = {
    inherit sourceInfo;
    pinnedRev = sourceInfo.rev;
    npmWrapperSrc = wrapperSrc;
    inherit bundledAcpx;
  };

  meta = with lib; {
    description = "Telegram-first AI gateway (OpenClaw)";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin ++ platforms.linux;
    mainProgram = "openclaw";
  };
}
