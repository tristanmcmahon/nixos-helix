{ lib, ... }:

{
  # Import only for a wiped installation first created on NixOS 26.05.
  system.stateVersion = lib.mkForce "26.05";
  environment.etc."helix/fresh-install-state-version".text = "26.05\n";
}
