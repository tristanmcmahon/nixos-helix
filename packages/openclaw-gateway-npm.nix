{
  lib,
  stdenv,
  buildNpmPackage,
  nodejs_22,
  nodejs-slim_22,
  makeWrapper,
  sourceInfo,
  bundledAcpx,
  upstreamSource,
}:

let
  # NixOS 26.05 links Node 22 against the shared nixpkgs SQLite 3.51.2, which
  # OpenClaw rejects because of the SQLite WAL-reset corruption bug. Keep Node
  # 22 but build it with its bundled SQLite. The assertion below fails loudly
  # if nixpkgs stops passing the shared-SQLite flags, so this override can then
  # be removed rather than silently becoming a no-op.
  isSharedSqliteFlag = flag: lib.hasPrefix "--shared-sqlite" flag;
  openclawNodeSlim = nodejs-slim_22.overrideAttrs (old: {
    configureFlags = builtins.filter (flag: !(isSharedSqliteFlag flag)) old.configureFlags;
  });
  openclawNode = nodejs_22.override {
    nodejs-slim = openclawNodeSlim;
  };
  buildNpmPackageForOpenClaw = buildNpmPackage.override {
    nodejs = openclawNode;
  };
  wrapperSrc = upstreamSource + "/nix/npm/openclaw";
  lock = builtins.fromJSON (builtins.readFile (wrapperSrc + "/package-lock.json"));
  lockedVersion = lock.packages."node_modules/openclaw".version or null;
in

assert lib.assertMsg (builtins.any isSharedSqliteFlag nodejs-slim_22.configureFlags)
  "nodejs-slim_22 no longer uses shared SQLite; remove the OpenClaw bundled-SQLite override";
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
