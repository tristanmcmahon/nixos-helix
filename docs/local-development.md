# Local development workflow

The non-flake `shell.nix` bootstraps the repository tools before the permanent
development profile is installed:

```bash
cd ~/Projects/nixos-helix
nix-shell
code .
```

It supplies VS Code, Git, GitHub CLI, Git LFS, Node.js/npm, `nil`, `nixfmt`,
ShellCheck, ripgrep, jq, and the OpenAI Codex CLI. VS Code is unfree, so
`shell.nix` permits unfree packages only for its own Nixpkgs import.

## VS Code and Nix

The workspace recommends `jnoortheen.nix-ide` and the verified official Codex
extension identifier, `openai.chatgpt`. Recommendations do not install or
authenticate extensions automatically.

The shared settings use `nil` as the single Nix language server and `nixfmt` as
the formatter, with format-on-save for Nix files. Start VS Code from `nix-shell`
so those binaries are on its inherited `PATH`.

Confirm extensions without changing them:

```bash
code --list-extensions --show-versions
```

## Codex

NixOS 25.11 packages the official OpenAI Codex CLI as `pkgs.codex`; the
development profile and bootstrap shell install it independently of VS Code.
The Codex IDE extension also bundles its own CLI, so installing VS Code alone
must not be treated as installing a user-facing terminal command.

If the NixOS package later becomes unavailable, the current official upstream
npm installation is:

```bash
npm install --global @openai/codex
```

Do not run a second global installation while the Nix package is active. Codex
authentication is per-user mutable state:

```bash
codex login
codex login status
```

Credentials and `~/.codex` state do not belong in this repository.

## Git and GitHub user state

Run these interactively as the user who will develop on Helix:

```bash
gh auth login
git lfs install
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

GitHub authentication, Git LFS filter setup, Git identity, extension state, and
Codex login are mutable per-user settings. NixOS installs the tools but should
not own those identities or credentials.

## Repository checks

Run the complete non-activating validation suite with:

```bash
./scripts/check.sh
```

The formatter check uses temporary copies and never rewrites source files.
