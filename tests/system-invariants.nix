let
  system = import <nixpkgs/nixos> { configuration = ../configuration.nix; };
  inherit (system) config;
  lib = system.pkgs.lib;
  release = import ../release.nix;
  localSsds = import ../system/local-ssds.nix;
  themePalette = import ../config/theme/palette.nix;
  mountOptions = [
    "noatime"
    "nofail"
    "x-systemd.device-timeout=5s"
  ];
  packageNames = map (package: package.pname or package.name or "") config.environment.systemPackages;
  infernalnexusMounts = builtins.filter (
    mount: mount.where == "/mnt/infernalnexus/nas1"
  ) config.systemd.mounts;
  infernalnexusAutomounts = builtins.filter (
    automount: automount.where == "/mnt/infernalnexus/nas1"
  ) config.systemd.automounts;
  infernalnexusMount = builtins.head infernalnexusMounts;
  infernalnexusAutomount = builtins.head infernalnexusAutomounts;
  infernalnexusOptions = builtins.filter builtins.isString (
    builtins.split "," infernalnexusMount.options
  );
  localSsdServiceName = ssd: "helix-storage-${ssd.id}-directories";
  localSsdServiceNames = map localSsdServiceName localSsds;
  configuredLocalSsdServiceNames = builtins.filter (
    name: lib.hasPrefix "helix-storage-" name && lib.hasSuffix "-directories" name
  ) (builtins.attrNames config.systemd.services);
  localSsdIsValid =
    ssd:
    let
      filesystem = config.fileSystems.${ssd.mountPoint};
      service = config.systemd.services.${localSsdServiceName ssd};
      mountUnit = "${lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" ssd.mountPoint)}.mount";
    in
    filesystem.device == "/dev/disk/by-label/${ssd.label}"
    && filesystem.fsType == "ext4"
    && filesystem.options == mountOptions
    && service.wantedBy == [ "multi-user.target" ]
    && builtins.elem mountUnit service.wants
    && builtins.elem mountUnit service.after
    && service.unitConfig.ConditionPathIsMountPoint == ssd.mountPoint
    && lib.hasInfix "mountpoint -q" service.script
    && lib.hasInfix ssd.mountPoint service.script
    && lib.hasInfix "${ssd.mountPoint}/data" service.script;
  context = {
    inherit
      config
      lib
      system
      release
      mountOptions
      localSsds
      localSsdIsValid
      configuredLocalSsdServiceNames
      localSsdServiceNames
      packageNames
      infernalnexusMounts
      infernalnexusAutomounts
      infernalnexusMount
      infernalnexusAutomount
      infernalnexusOptions
      themePalette
      ;
  };
in
assert import ./invariants/core.nix context;
assert import ./invariants/monitoring.nix context;
assert import ./invariants/storage.nix context;
assert import ./invariants/desktop.nix context;
assert import ./invariants/emulation.nix context;
assert import ./invariants/llm.nix context;
assert import ./invariants/network-security.nix context;
true
