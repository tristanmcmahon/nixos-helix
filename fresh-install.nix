{ lib, ... }:

let
  release = import ./release.nix;
in
{
  # Import only for a wiped installation first created on the target release.
  system.stateVersion = lib.mkForce release.freshStateVersion;
  environment.etc."helix/fresh-install-state-version".text = "${release.freshStateVersion}\n";
}
