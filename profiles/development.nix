{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.helix.development;

  # Explicit, user-run helper: Zed reads agent_servers only from user settings.
  zedAgentSetup = pkgs.writeShellApplication {
    name = "helix-zed-agent-setup";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${../scripts/helix-zed-agent-setup.py} "$@"
    '';
  };
  # Nixpkgs installs Zed as `zeditor`; `zed` is the name people type. hiPrio
  # makes this win over any other package that also ships a `zed` binary.
  zedAlias = lib.hiPrio (
    pkgs.writeShellScriptBin "zed" ''
      exec zeditor "$@"
    ''
  );
in
{
  # Editors, publishing tools, coding agents, compilers and runtimes. This adds
  # no system service policy; it is a boundary so the set can be disabled.
  options.helix.development.enable = lib.mkEnableOption "the development toolset";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      vscode
      zed-editor
      zedAlias
      helix
      gh
      git-lfs
      codex
      claude-code
      claude-agent-acp
      zedAgentSetup
      (callPackage ../packages/hamllm.nix { })

      fzf
      dust

      gcc
      gnumake
      pkg-config
      python3
      # The Nixpkgs Node.js package includes npm.
      nodejs
      nil
      nixfmt
      shellcheck
    ];
  };
}
