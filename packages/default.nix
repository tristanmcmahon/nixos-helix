{ ... }:

{
  # Feature package sets are imported by their owning profiles. Only the
  # deliberately small always-present package set enters here.
  imports = [ ./base.nix ];
}
