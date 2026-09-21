context:
let
  inherit (context) config lib packageNames;
in
assert config.helix.emulation.enable;
assert config.helix.hamCade.enable;
assert builtins.elem "hamcade" packageNames;
assert builtins.hasAttr "helix-emulation-prepare" config.systemd.user.services;
assert builtins.elem "helix-retroarch" packageNames;
assert builtins.elem "helix-emulation-status" packageNames;
assert builtins.any (
  mount:
  mount.where == "/mnt/infernalnexus/roms"
  && mount.what == "//192.168.1.8/roms"
  && lib.hasInfix ",ro" mount.options
) config.systemd.mounts;
assert
  config.systemd.services."helix-emulation-storage".unitConfig.ConditionPathIsMountPoint
  == "/mnt/games_nvme";
assert lib.hasInfix "/mnt/games_nvme/emulation"
  config.systemd.services."helix-emulation-storage".script;
true
