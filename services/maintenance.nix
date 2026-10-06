_:

{
  # Firmware updates remain explicitly initiated through fwupdmgr.
  services.fwupd.enable = true;

  nix = {
    # Ad-hoc nix-shell, nix-build and a bare nixos-rebuild use the same pinned
    # Nixpkgs as the repository scripts, never a separately updated channel.
    nixPath = [
      "nixpkgs=${import ../nixpkgs.nix}"
      "nixos-config=${(import ../config/helix.nix).checkout}/configuration.nix"
    ];

    # Native NixOS garbage collection avoids a repository-owned generation
    # parser. Recent generations remain available through this age-based policy.
    gc = {
      automatic = true;
      dates = "weekly";
      persistent = true;
      randomizedDelaySec = "60min";
      options = "--delete-older-than 14d";
    };

    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };

    # Builds use only spare CPU, so a large local build (OpenClaw's Node, the
    # NVIDIA module after a kernel bump) cannot make the desktop, a game or a
    # local model stutter. On an otherwise idle machine they run at full speed.
    # The matching I/O class is not set: NVMe uses no I/O scheduler, so it
    # would have no effect.
    daemonCPUSchedPolicy = "idle";
  };
}
