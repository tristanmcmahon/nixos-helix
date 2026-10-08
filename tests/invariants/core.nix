context:
let
  inherit (context)
    config
    system
    release
    packageNames
    ;
in
assert config.system.nixos.release == release.nixosRelease;
assert config.system.stateVersion == release.stateVersion;
assert config.nix.gc.automatic;
assert config.nix.gc.options == "--delete-older-than 14d";
assert config.nix.optimise.automatic;
# Local builds must never starve interactive work.
assert config.nix.daemonCPUSchedPolicy == "idle";
assert config.zramSwap.enable;
assert config.zramSwap.algorithm == "zstd";
assert config.zramSwap.memoryPercent == 50;
assert config.zramSwap.priority == 100;
assert config.systemd.oomd.enable;
assert config.systemd.oomd.enableRootSlice;
assert config.systemd.oomd.enableUserSlices;
assert !config.systemd.oomd.enableSystemSlice;
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
assert builtins.elem "helix-git-credential-repair" packageNames;
assert builtins.elem "gh" packageNames;
assert !(builtins.elem "zen-browser" packageNames);
assert builtins.elem "claude-code" packageNames;
assert builtins.elem "claude-agent-acp" packageNames;
assert builtins.elem "helix-zed-agent-setup" packageNames;
# `zed` must open the editor, not another package's `zed` CLI.
assert builtins.elem "zed" packageNames;
# hamology backups run unattended as the user, keep exactly the two newest
# archives, and do not depend on a login session.
assert
  config.systemd.services.hamology-backup.serviceConfig.ExecStart
  == "${system.pkgs.bash}/bin/bash /home/tristan/Projects/hamology/scripts/hamology-backup --unattended --keep 2";
assert config.systemd.services.hamology-backup.serviceConfig.User == "tristan";
assert config.systemd.timers.hamology-backup.timerConfig.Persistent;
assert !(builtins.hasAttr "hamology-backup" config.systemd.user.services);
# No user lingering: it would start every user unit at boot without a login.
assert config.users.users.tristan.linger != true;
assert !(builtins.elem "codex-acp" packageNames);
assert builtins.elem "helix-theme" packageNames;
assert builtins.compareVersions system.pkgs.openclaw.version "2026.6.9" >= 0;
assert system.pkgs.openclaw.version == "2026.7.1-2";
# OpenClaw writes beside its config; a /nix/store config path fails with EROFS.
assert
  !(system.pkgs.lib.hasPrefix builtins.storeDir config.systemd.user.services.openclaw-gateway.environment.OPENCLAW_CONFIG_PATH);
# Repository paths that configure commands run outside the OpenClaw sandbox.
assert builtins.all
  (
    path:
    builtins.elem "-/home/tristan/Projects/nixos-helix/${path}" config.systemd.user.services.openclaw-gateway.serviceConfig.ReadOnlyPaths
  )
  [
    ".git"
    ".vscode"
    ".zed"
    ".claude"
  ];
# The health gate covers every critical unit of the enabled features.
assert builtins.all (unit: builtins.elem unit config.helix.health.criticalUnits) [
  "sshd.service"
  "ollama.service"
  "netdata.service"
  "coolercontrold.service"
];
assert config.helix.health.criticalUserUnits == [ "openclaw-gateway.service" ];
# NIX_PATH exposes the repository's pinned Nixpkgs, not a moving channel.
assert builtins.elem "nixpkgs=${import ../../nixpkgs.nix}" config.nix.nixPath;
# Routine backups go to the NAS, cover the unrecreatable state, and keep the
# password outside the store.
assert
  let
    backup = config.services.restic.backups.helix;
  in
  system.pkgs.lib.hasPrefix "/mnt/infernalnexus/nas1/" backup.repository
  && !(system.pkgs.lib.hasPrefix builtins.storeDir backup.passwordFile)
  && builtins.all (path: builtins.elem path backup.paths) [
    "/home/tristan"
    "/etc/nixos/secrets"
    "/etc/ssh"
  ];
# Unfree software is allowed by name only, never wholesale.
assert !(config.nixpkgs.config.allowUnfree or false);
assert (config.nixpkgs.config.permittedInsecurePackages or [ ]) == [ ];
assert builtins.elem "evtest" packageNames;
assert config.environment.variables.EDITOR == "vim";
assert config.environment.variables.VISUAL == "vim";
assert builtins.any (name: builtins.match "vim.*" name != null) packageNames;
assert config.systemd.user.services."helix-git-credential-helper".serviceConfig.ExecStart != "";
true
