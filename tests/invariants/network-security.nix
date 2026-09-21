context:
let
  inherit (context)
    config
    infernalnexusMounts
    infernalnexusAutomounts
    infernalnexusMount
    infernalnexusAutomount
    infernalnexusOptions
    ;
in
assert config.hardware.ckb-next.enable;
assert config.services.openssh.enable;
assert config.services.openssh.openFirewall;
assert config.services.openssh.ports == [ 22 ];
assert config.services.openssh.settings.PermitRootLogin == "no";
assert config.services.openssh.settings.PubkeyAuthentication;
assert !config.services.openssh.settings.PasswordAuthentication;
assert !config.services.openssh.settings.KbdInteractiveAuthentication;
assert config.networking.hosts."192.168.1.2" == [ "mister" ];
assert config.networking.hosts."192.168.1.8" == [ "infernalnexus" ];
assert !(builtins.hasAttr "/mnt/infernalnexus/nas1" config.fileSystems);
assert builtins.length infernalnexusMounts == 1;
assert infernalnexusMount.what == "//192.168.1.8/nas1";
assert infernalnexusMount.type == "cifs";
assert builtins.all (option: builtins.elem option infernalnexusOptions) [
  "credentials=/etc/nixos/secrets/infernalnexus-smb"
  "uid=tristan"
  "gid=users"
  "dir_mode=0775"
  "file_mode=0664"
];
assert builtins.elem "vers=2.0" infernalnexusOptions;
assert builtins.elem "sec=ntlmssp" infernalnexusOptions;
assert !(builtins.elem "vers=1.0" infernalnexusOptions);
assert !(builtins.elem "x-systemd.automount" infernalnexusOptions);
assert builtins.all (
  option: builtins.match "x-systemd\\.(mount-timeout|idle-timeout).*" option == null
) infernalnexusOptions;
assert builtins.elem "network-online.target" infernalnexusMount.wants;
assert builtins.elem "network-online.target" infernalnexusMount.after;
assert infernalnexusMount.mountConfig.TimeoutSec == "15s";
assert builtins.length infernalnexusAutomounts == 1;
assert builtins.elem "multi-user.target" infernalnexusAutomount.wantedBy;
assert infernalnexusAutomount.automountConfig.TimeoutIdleSec == "10min";
assert config.networking.firewall.enable;
assert builtins.elem 22 config.networking.firewall.allowedTCPPorts;
assert builtins.hasAttr "sshd" config.systemd.services;
true
