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
    nix-output-monitor
    nvd
  ];

  # Use the supported NixOS module so Vim is also exposed as `vi` and becomes
  # the recovery editor selected by EDITOR and VISUAL.
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  # Keep the recovery-shell contract explicit for tools that read VISUAL.
  environment.variables.VISUAL = "vim";
}
