{ ... }:

{
  # fwupd exposes firmware devices and applies only updates explicitly approved
  # through `fwupdmgr`; merely enabling the daemon does not flash anything.
  services.fwupd.enable = true;

  # Store optimisation hard-links identical Nix store files. It is safe for all
  # generations and avoids the rollback loss caused by aggressive automatic
  # garbage collection, which is deliberately not enabled at this stage.
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
}
