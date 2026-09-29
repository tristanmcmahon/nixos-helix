{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # EXPERIMENTAL: editor-agent integration. Keep this branch unmerged until
    # Helix has completed a real dry-build and temporary activation.
    (vscode-with-extensions.override {
      vscodeExtensions = with vscode-extensions; [
        jnoortheen.nix-ide
        anthropic.claude-code
      ];
    })
    zed-editor
    helix
    gh
    git-lfs
    codex
    claude-code
    codex-acp
    claude-agent-acp
    (callPackage ./hamllm.nix { })

    bottom
    ripgrep
    fd
    bat
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
