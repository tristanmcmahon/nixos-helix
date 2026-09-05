_:

let
  packageSource = builtins.fetchTarball {
    url = "https://github.com/openclaw/nix-openclaw/archive/d3760a6f103642f11e24bc01ee9aec80a0153774.tar.gz";
    sha256 = "1pfzr2c94x0f77qwpnb9gvvfvvsz59fgybpjwhb9fsrhlv1zli6y";
  };
in
{
  nixpkgs.overlays = [
    (import "${packageSource}/nix/overlay.nix" {
      openclawToolPkgs = { };
      qmdPkgs = { };
    })
  ];
}
