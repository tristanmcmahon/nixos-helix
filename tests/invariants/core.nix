context:
let
  inherit (context) config system release packageNames;
in
assert config.system.nixos.release == release.nixosRelease;
assert config.system.stateVersion == release.stateVersion;
assert config.nix.gc.automatic;
assert config.nix.gc.options == "--delete-older-than 14d";
assert config.nix.optimise.automatic;
assert config.zramSwap.enable;
assert config.zramSwap.algorithm == "zstd";
assert config.zramSwap.memoryPercent == 50;
assert config.zramSwap.priority == 100;
assert config.systemd.oomd.enable;
assert config.systemd.oomd.enableRootSlice;
assert config.systemd.oomd.enableUserSlices;
assert !config.systemd.oomd.enableSystemSlice;
assert !(builtins.elem "chatgpt" packageNames);
assert builtins.elem "adwsteamgtk" packageNames;
assert builtins.elem "doomrunner" packageNames;
assert builtins.elem "gzdoom" packageNames;
assert builtins.elem "uzdoom" packageNames;
assert builtins.elem "protonplus" packageNames;
assert builtins.elem "protontricks" packageNames;
assert builtins.elem "goverlay" packageNames;
assert builtins.elem "nix-output-monitor" packageNames;
assert builtins.elem "nvd" packageNames;
assert builtins.elem "helix-health" packageNames;
assert builtins.elem "helix-update" packageNames;
assert builtins.elem "helix-theme" packageNames;
assert builtins.compareVersions system.pkgs.openclaw.version "2026.6.9" >= 0;
assert system.pkgs.openclaw.version == "2026.7.1-2";
assert (config.nixpkgs.config.permittedInsecurePackages or [ ]) == [ ];
assert builtins.elem "evtest" packageNames;
assert config.environment.variables.EDITOR == "vim";
assert config.environment.variables.VISUAL == "vim";
assert builtins.any (name: builtins.match "vim.*" name != null) packageNames;
true
