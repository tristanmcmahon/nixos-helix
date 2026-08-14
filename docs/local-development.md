# Local development workflow

The non-flake `shell.nix` is the minimal bootstrap and repository-check
environment, including installer use. It contains only Git, Python, nixfmt,
ShellCheck, Deadnix, and Statix:

```bash
cd ~/Projects/nixos-helix
./scripts/dev-shell.sh
```

The helper selects an explicit `HELIX_NIXPKGS_PATH` when provided, otherwise
the installed root NixOS channel, and refuses a release other than the `26.05`
contract. This prevents ambient user `NIX_PATH` state from changing evaluation.
Run a single command in the same environment with:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
```

The installed workstation development environment is separately owned by
`profiles/development.nix` and `packages/development.nix`. That maintained
system profile contains VS Code, GitHub CLI, Git LFS, Codex, Node.js, `nil`,
compilers, runtimes, and the other daily development tools. Do not expand the
bootstrap shell to duplicate that workstation profile.

## VS Code and Nix

The workspace recommends `jnoortheen.nix-ide` and the verified official Codex
extension identifier, `openai.chatgpt`. Recommendations do not install or
authenticate extensions automatically.

The shared settings use `nil` as the single Nix language server and `nixfmt` as
the formatter, with format-on-save for Nix files. On the installed workstation,
launch `code .` from the ordinary user environment supplied by the maintained
development profile; VS Code is intentionally absent from `shell.nix`.

Confirm extensions without changing them:

```bash
code --list-extensions --show-versions
```

## Codex

NixOS 26.05 packages the official OpenAI Codex CLI as `pkgs.codex`; the
installed development profile provides it independently of VS Code.
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
evaluates repository invariants and builds the canonical NixOS 26.05
configuration with its 26.05 compatibility floor. Checking and building do not
activate; dry activation previews changes, `test` changes the running system,
and `switch` also changes the persistent boot selection. Reboot and destructive
reinstall remain separate human actions.
