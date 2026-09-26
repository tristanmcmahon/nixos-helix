# hamCade vendor snapshot

This directory is an integration boundary, not a fork of hamCade.

`hamCade/dependencies.nix` is the canonical dependency definition for the
arcade application. `dependencies.nix` here is a vendored snapshot of that
file so `nixos-helix` can evaluate and run CI without GitHub credentials for
the private sibling repository.

The source hamCade commit is recorded in the snapshot header. When hamCade
changes its runtime dependencies:

1. update and validate `dependencies.nix` in the hamCade repository first;
2. copy that file here without changing its dependency choices;
3. add/update the source-commit provenance comment in this snapshot;
4. run the normal `nixos-helix` validation before merging.

Do not add hamCade application logic, curation rules, DAT/audit code or mutable
arcade state to this directory. The only owner of those behaviours is hamCade.
