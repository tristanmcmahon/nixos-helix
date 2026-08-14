let
  system = import <nixpkgs/nixos> { configuration = ../configuration.nix; };
  inherit (system) config;
  lib = system.pkgs.lib;
  release = import ../release.nix;
  localSsds = import ../system/local-ssds.nix;
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
in
assert config.system.nixos.release == release.nixosRelease;
assert config.system.stateVersion == release.stateVersion;
assert config.nix.gc.automatic;
assert config.nix.gc.options == "--delete-older-than 30d";
assert config.nix.optimise.automatic;
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
assert config.services.desktopManager.plasma6.enable;
assert config.services.displayManager.sddm.enable;
assert config.programs.hyprland.enable;
assert config.programs.hyprland.withUWSM;
assert config.services.xserver.videoDrivers == [ "nvidia" ];
assert config.hardware.graphics.enable;
assert config.hardware.graphics.enable32Bit;
assert config.hardware.nvidia.modesetting.enable;
assert config.hardware.nvidia.open;
assert config.hardware.nvidia.powerManagement.enable;
assert config.programs.steam.enable;
assert config.programs.gamemode.enable;
assert config.services.ollama.enable;
assert config.services.ollama.host == "127.0.0.1";
assert !config.services.ollama.openFirewall;
assert config.services.ollama.package == system.pkgs.ollama-cuda;
assert config.services.ollama.user == "ollama";
assert config.services.ollama.group == "ollama";
assert config.services.ollama.models == "/mnt/games_nvme/ollama/models";
assert config.services.ollama.loadModels == [ ];
assert !config.services.ollama.syncModels;
assert builtins.hasAttr "ollama" config.systemd.services;
assert !(builtins.hasAttr "ollama-model-loader" config.systemd.services);
assert builtins.elem "helix-ollama-model-storage.service" config.systemd.services.ollama.requires;
assert builtins.elem "helix-ollama-model-storage.service" config.systemd.services.ollama.after;
assert
  config.systemd.services.helix-ollama-model-storage.unitConfig.ConditionPathIsMountPoint
  == "/mnt/games_nvme";
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
assert config.programs._1password.enable;
assert config.programs._1password-gui.enable;
assert config.programs._1password-gui.polkitPolicyOwners == [ "tristan" ];
assert config.programs.chromium.enable;
assert
  config.programs.chromium.extensions == [
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    "eimadpbcbfnmbkopoojfekhnkhdbieeh"
  ];
assert config.programs.chromium.extraOpts.BrowserThemeColor == "#030405";
assert !config.programs.chromium.extraOpts.PasswordManagerEnabled;
assert config.programs.firefox.enable;
assert !config.programs.firefox.policies.OfferToSaveLogins;
assert builtins.hasAttr "addon@darkreader.org" config.programs.firefox.policies.ExtensionSettings;
assert config.programs.firefox.preferences."ui.systemUsesDarkTheme" == 1;
assert config.services.displayManager.sddm.theme == "helix-abyss";
assert config.programs.dconf.enable;
assert config.systemd.user.services.helix-abyss-theme.unitConfig.ConditionUser == "tristan";
assert config.systemd.user.services.helix-ghostty-config.unitConfig.ConditionUser == "tristan";
assert builtins.elem "HOME=/home/tristan"
  config.systemd.user.services.helix-ghostty-config.serviceConfig.Environment;
assert builtins.elem "XDG_CONFIG_HOME=/home/tristan/.config"
  config.systemd.user.services.helix-ghostty-config.serviceConfig.Environment;
assert !(builtins.hasAttr "GTK_THEME" config.environment.variables);
assert !(builtins.hasAttr "QT_STYLE_OVERRIDE" config.environment.variables);
assert !(builtins.hasAttr "QT_QPA_PLATFORMTHEME" config.environment.variables);
assert builtins.all (name: builtins.elem name packageNames) [
  "spotify"
  "vlc"
  "haruna"
  "strawberry"
  "plex-desktop"
  "gridplayer"
];
assert builtins.all (name: builtins.elem name packageNames) [
  "signal-desktop"
  "pidgin"
  "ollama"
];
assert builtins.any (name: builtins.match "mpv.*" name != null) packageNames;
assert !(builtins.elem "plexmediaserver" packageNames);
assert builtins.hasAttr "ckb-next" config.systemd.services;
assert config.environment.variables.EDITOR == "vim";
assert config.environment.variables.VISUAL == "vim";
assert builtins.any (name: builtins.match "vim.*" name != null) packageNames;
true
