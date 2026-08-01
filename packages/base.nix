{ pkgs, ... }:

{
  # Keep this list suitable for every Helix installation, including systems
  # without a desktop or development toolchain.
  environment.systemPackages = with pkgs; [
    git
    vim
    curl
    wget
    file
    tree
  ];

  # Use the supported NixOS module so Vim is also exposed as `vi` and becomes
  # the recovery editor selected by EDITOR and VISUAL.
  programs.vim = {
    enable = true;
    defaultEditor = true;
  };

  # NixOS' Vim module sets EDITOR but not VISUAL in 25.11.
  environment.variables.VISUAL = "vim";
}
