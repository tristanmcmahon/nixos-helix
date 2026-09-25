_:

let
  packageSource = builtins.fetchTarball {
    url = "https://github.com/openclaw/nix-openclaw/archive/d3760a6f103642f11e24bc01ee9aec80a0153774.tar.gz";
    sha256 = "1pfzr2c94x0f77qwpnb9gvvfvvsz59fgybpjwhb9fsrhlv1zli6y";
  };
in
{
  nixpkgs.overlays = [
    (
      final: prev:
      let
        sourceInfo = import "${packageSource}/nix/sources/openclaw-source.nix";
        runtimePluginLocks = import "${packageSource}/nix/generated/openclaw-runtime-plugins";
        buildBundledRuntimePlugin =
          prev.callPackage "${packageSource}/nix/lib/openclaw-runtime-plugin.nix"
            {
              linkOpenClawPeer = false;
            };
        bundledAcpx = buildBundledRuntimePlugin runtimePluginLocks.acpx;

        # The upstream flake reads its npm wrapper lock through a stringified
        # subdirectory path. Helix consumes the same immutable source as a
        # tarball overlay, where that coercion can produce an unrealised store
        # path during evaluation. Keep the upstream package logic but make the
        # wrapper source an explicit path in the local compatibility definition.
        openclawGateway = prev.callPackage ./openclaw-gateway-npm.nix {
          upstreamSource = packageSource;
          inherit sourceInfo bundledAcpx;
        };

        toolSets = import "${packageSource}/nix/tools/extended.nix" {
          pkgs = prev;
          openclawToolPkgs = { };
        };

        openclawBundle = prev.callPackage "${packageSource}/nix/packages/openclaw-batteries.nix" {
          openclaw-gateway = openclawGateway;
          openclaw-app = null;
          extendedTools = toolSets.tools;
          version = sourceInfo.releaseVersion;
        };
      in
      {
        openclaw-gateway = openclawGateway;
        openclaw = openclawBundle;
      }
    )
  ];
}
