_:

{
  # Firmware updates remain explicitly initiated through fwupdmgr.
  services.fwupd.enable = true;

  # Native NixOS garbage collection avoids a repository-owned generation
  # parser. Recent generations remain available through this age-based policy.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    persistent = true;
    randomizedDelaySec = "60min";
    options = "--delete-older-than 30d";
  };

  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
}
