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
in
assert !config.helix.emulation.enable;
assert !(builtins.any (mount: mount.where == "/mnt/infernalnexus/roms") config.systemd.mounts);
assert
  !(builtins.any (automount: automount.where == "/mnt/infernalnexus/roms") config.systemd.automounts);
assert !(builtins.elem "helix-emulation-prepare" packageNames);
assert !(builtins.hasAttr "helix-emulation-prepare" config.systemd.user.services);
true
