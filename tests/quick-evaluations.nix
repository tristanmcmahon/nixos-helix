# Evaluate all four invariants in one Nix interpreter invocation. Each imported
# test still contains its original assertions and feature-toggle boundaries.
let
  checks = [
    {
      name = "production";
      file = ./system-invariants.nix;
    }
    {
      name = "monitoring-disabled";
      file = ./monitoring-disabled.nix;
    }
    {
      name = "emulation-disabled";
      file = ./emulation-disabled.nix;
    }
    {
      name = "features-disabled";
      file = ./features-disabled.nix;
    }
  ];
  verify =
    check:
    let
      result = import check.file;
    in
    if result == true then true else throw "Helix invariant ${check.name} returned a non-true result";
in
builtins.all verify checks
