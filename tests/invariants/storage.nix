context:
let
  inherit (context) config mountOptions localSsds localSsdIsValid configuredLocalSsdServiceNames localSsdServiceNames;
in
assert
  config.fileSystems."/mnt/games_nvme".device
  == "/dev/disk/by-uuid/d07ac88e-34f6-4d56-9941-5ceaf52fd6bb";
assert config.fileSystems."/mnt/games_nvme".fsType == "ext4";
assert config.fileSystems."/mnt/games_nvme".options == mountOptions;
assert builtins.length localSsds == 3;
assert builtins.all localSsdIsValid localSsds;
assert
  builtins.sort builtins.lessThan configuredLocalSsdServiceNames
  == builtins.sort builtins.lessThan localSsdServiceNames;
assert config.services.fstrim.enable;
true
