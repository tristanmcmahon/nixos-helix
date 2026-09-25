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
        # nix-openclaw normally consumes this tree as a flake input. Helix
        # imports the overlay from a pinned tarball instead, which exposes an
        # evaluation issue when the wrapper directory is coerced to a store
        # string before builtins.readFile. Patch with the unmodified previous
        # package set so defining this overlay cannot recurse through pkgs.
        patchedPackageSource = prev.applyPatches {
          name = "nix-openclaw-d3760a6-helix";
          src = packageSource;
          patches = [ ../patches/nix-openclaw-wrapper-readfile.patch ];
        };
        upstreamOverlay = import "${patchedPackageSource}/nix/overlay.nix" {
          openclawToolPkgs = { };
          qmdPkgs = { };
        };
      in
      upstreamOverlay final prev
    )
  ];
}
