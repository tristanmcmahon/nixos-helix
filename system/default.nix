{ ... }:

{
  imports = [
    ./boot.nix
    ./hosts.nix
    ./networking.nix
    ./nas.nix
    ./storage.nix
    ./users.nix
    ./locale.nix
  ];
}
