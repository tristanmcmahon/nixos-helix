context:
let
  inherit (context) config packageNames themePalette;
in
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
assert config.programs.gamescope.enable;
assert !config.programs.gamescope.capSysNice;
assert config.hardware.steam-hardware.enable;
assert config.hardware.bluetooth.enable;
assert !config.hardware.xpadneo.enable;
assert builtins.elem "hid_playstation" config.boot.kernelModules;
assert builtins.elem "hid_xpadneo" config.boot.blacklistedKernelModules;
assert config.programs._1password.enable;
assert config.programs._1password-gui.enable;
assert config.programs._1password-gui.polkitPolicyOwners == [ "tristan" ];
assert config.programs.chromium.enable;
assert
  config.programs.chromium.extensions == [
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
    "eimadpbcbfnmbkopoojfekhnkhdbieeh"
  ];
assert config.programs.chromium.extraOpts.BrowserThemeColor == themePalette.background;
assert !config.programs.chromium.extraOpts.PasswordManagerEnabled;
assert config.programs.firefox.enable;
assert !config.programs.firefox.policies.OfferToSaveLogins;
assert builtins.hasAttr "addon@darkreader.org" config.programs.firefox.policies.ExtensionSettings;
assert config.programs.firefox.preferences."ui.systemUsesDarkTheme" == 1;
assert config.services.displayManager.sddm.theme == "helix-graphite-fern";
assert config.programs.dconf.enable;
assert config.systemd.user.services.helix-graphite-fern-theme.unitConfig.ConditionUser == "tristan";
assert config.systemd.user.services.helix-ghostty-config.unitConfig.ConditionUser == "tristan";
assert builtins.elem "HOME=/home/tristan"
  config.systemd.user.services.helix-ghostty-config.serviceConfig.Environment;
assert builtins.elem "XDG_CONFIG_HOME=/home/tristan/.config"
  config.systemd.user.services.helix-ghostty-config.serviceConfig.Environment;
assert builtins.all (name: builtins.elem name packageNames) [
  "ghostty-profile"
  "ghostty-surface-profile"
  "ghostty-surface-shell"
];
assert !(builtins.elem "ghostty-split-profile" packageNames);
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
  "helix-ollama-update-models"
];
assert builtins.any (name: builtins.match "mpv.*" name != null) packageNames;
assert !(builtins.elem "plexmediaserver" packageNames);
assert builtins.hasAttr "ckb-next" config.systemd.services;
true
