let
  system = import <nixpkgs/nixos> {
    configuration = {
      imports = [ ../profiles/emulation.nix ];
      helix.emulation.enable = false;
      system.stateVersion = "26.05";
    };
  };
  inherit (system) config;
  packageNames = map (package: package.pname or package.name or "") config.environment.systemPackages;
  emulationPackageNames = [
    "helix-emulation-require-nas"
    "helix-emulation-discover"
    "helix-emulation-prepare"
    "helix-emulation-index-dats"
    "helix-emulation-audit-arcade"
    "helix-emulation-scrape"
    "helix-emulation-status"
    "helix-pcsx2"
    "helix-rpcs3"
    "helix-shadps4"
    "helix-mame"
    "helix-retroarch"
  ];
in
assert !config.helix.emulation.enable;
assert !(builtins.any (mount: mount.where == "/mnt/infernalnexus/roms") config.systemd.mounts);
assert
  !(builtins.any (automount: automount.where == "/mnt/infernalnexus/roms") config.systemd.automounts);
assert builtins.all (name: !(builtins.elem name packageNames)) emulationPackageNames;
assert !(builtins.hasAttr "helix-emulation-prepare" config.systemd.user.services);
true
