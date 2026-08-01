let
  pkgs = import <nixpkgs> {
    # VS Code is unfree; keep this exception local to the bootstrap shell.
    config.allowUnfree = true;
  };
in
pkgs.mkShell {
  packages = with pkgs; [
    vscode
    git
    gh
    git-lfs
    nodejs
    nil
    nixfmt-rfc-style
    shellcheck
    ripgrep
    jq
    codex
  ];
}
