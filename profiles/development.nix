{ ... }:

{
  # Keep development independently removable even though it currently needs no
  # system policy beyond its package set.
  imports = [ ../packages/development.nix ];
}
