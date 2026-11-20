# Share the expensive production NixOS evaluation with its monitoring-off case.
assert import ./system-invariants.nix;
assert import ./monitoring-disabled.nix;
true
