# Report all failing invariant modules under one Nix evaluator. A non-true
# result or an assertion failure counts as failure; evaluation is shared.
checks:
let
  outcomes = map (check: {
    inherit (check) name;
    passed = (builtins.tryEval (if check.value == true then true else throw "non-true check")).success;
  }) checks;
  failures = builtins.filter (result: !result.passed) outcomes;
  names = builtins.concatStringsSep ", " (map (result: result.name) failures);
in
if failures == [ ] then
  true
else
  throw "Helix invariant modules failed: ${names}. Inspect tests/invariants/ for those modules."
