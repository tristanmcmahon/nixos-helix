{ pkgs, ... }:

{
  # Keep this list suitable for every Helix installation, including systems
  # without a desktop or development toolchain.
  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    file
    tree
  ];
}
