# Local development workflow

The non-flake `shell.nix` bootstraps the repository tools before the permanent
development profile is installed:

```bash
cd ~/Projects/nixos-helix
./scripts/dev-shell.sh
code .
```

The helper selects the root NixOS channel deterministically and refuses a
release other than the `26.05` contract. This prevents user `NIX_PATH` state
from making checks evaluate a different package set from root rebuilds. Run a
single command in the same environment with:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
```

It supplies VS Code, Git, GitHub CLI, Git LFS, Node.js/npm, `nil`, `nixfmt`,
ShellCheck, ripgrep, jq, and the OpenAI Codex CLI. VS Code is unfree, so
`shell.nix` permits unfree packages only for its own Nixpkgs import. It also
includes deadnix and statix for the repository's Nix maintenance checks.

## VS Code and Nix

The workspace recommends `jnoortheen.nix-ide` and the verified official Codex
extension identifier, `openai.chatgpt`. Recommendations do not install or
authenticate extensions automatically.

The shared settings use `nil` as the single Nix language server and `nixfmt` as
the formatter, with format-on-save for Nix files. Start VS Code from `./scripts/dev-shell.sh`
so those binaries are on its inherited `PATH`.

Confirm extensions without changing them:

```bash
code --list-extensions --show-versions
```

## Codex

NixOS 26.05 packages the official OpenAI Codex CLI as `pkgs.codex`; the
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
./scripts/dev-shell.sh --run './scripts/check.sh'
```

The formatter, Deadnix, and Statix checks exclude only the generated
`hardware-configuration.nix`. Maintained modules remain fully checked, and the
formatter uses temporary copies without rewriting source files. The suite
evaluates and builds the existing-install entry point (26.05 release, 25.11
state version) separately from the wiped fresh-install entry point (26.05 for
both). Checking and building do not activate; dry activation previews changes,
`test` changes the running system, and `switch` also changes the persistent boot
selection. Reboot and destructive reinstall remain separate human actions.
