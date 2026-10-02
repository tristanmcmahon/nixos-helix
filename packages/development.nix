{ pkgs, ... }:

let
  # Explicit, user-run helper: Zed reads agent_servers only from user settings.
  zedAgentSetup = pkgs.writeShellApplication {
    name = "helix-zed-agent-setup";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${../scripts/helix-zed-agent-setup.py} "$@"
    '';
  };
in
{
  environment.systemPackages = with pkgs; [
    vscode
    zed-editor
    helix
    gh
    git-lfs
    codex
    claude-code
    claude-agent-acp
    zedAgentSetup
    (callPackage ./hamllm.nix { })

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
}
