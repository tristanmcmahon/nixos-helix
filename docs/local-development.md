# Local development workflow

The non-flake `shell.nix` is the minimal bootstrap and repository-check
environment, including installer use. It contains only Git, Python, nixfmt,
ShellCheck, Deadnix, and Statix:

```bash
cd ~/Projects/nixos-helix
./scripts/dev-shell.sh
```

The helper selects an explicit `HELIX_NIXPKGS_PATH` when provided, otherwise
the release pinned in `nixpkgs.json`, and refuses a release other than the `26.05`
contract. This prevents ambient user `NIX_PATH` state from changing evaluation.
Run a single command in the same environment with:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
```

The installed workstation development environment is separately owned by
`profiles/development.nix` (`helix.development.enable`). That maintained
system profile contains VS Code, Zed, the Helix editor, hamLLM, GitHub CLI, Git
LFS, Codex, Claude Code and its Zed ACP adapter, Node.js, `nil`, compilers,
runtimes, and the other daily development tools. Do not expand the
bootstrap shell to duplicate that workstation profile.

## Local models and editors

The local-LLM profile runs Ollama on `127.0.0.1:11434`. The development profile
packages hamLLM's CLI from the pinned source snapshot under `vendor/hamllm`.
The snapshot is packaging input only: shared model and agent code is maintained
in the separate hamLLM repository. Inspect the actual running service with:

```bash
hamllm doctor
ollama list
ollama ps
```

Zed is available alongside VS Code and `hx`; the NixOS package launches it as
`zeditor` (for example `zeditor .`), not `zed`. Zed's Ollama provider connects
directly to the loopback service; it does not run through hamLLM. Select an
installed model in Zed and set its Ollama context window explicitly to match
the service's 32768-token configuration, since editor request defaults can be
smaller. Keep personal editor settings under `~/.config/zed/` rather than in
the system configuration. Local model chat/agent features and edit prediction
have separate Zed settings.

The Codex and Claude Code CLIs are independent of the editors and use their own
authentication and model access. Installing a local Ollama service does not
make either service-backed agent local.

Helix's editor split is deliberate: VS Code is used with Codex, and Zed is used
with Claude Code.

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

## Claude Code

NixOS 26.05 packages Claude Code as `pkgs.claude-code` and its Agent Client
Protocol adapter as `pkgs.claude-agent-acp`; the development profile installs
both instead of Anthropic's native installer or a global npm install. The Nix
package owns updates, so do not run `claude update`.

After switching the system, verify the packaged binary and authenticate
interactively:

```bash
claude --version
claude doctor
claude
```

Zed reads `agent_servers` only from user settings, not from a project's
`.zed/settings.json`. Register the adapter once with the explicit helper:

```bash
helix-zed-agent-setup
```

The helper edits only `agent_servers."Claude Code"` in
`~/.config/zed/settings.json`. It records the PATH-resolved
`claude-agent-acp` command rather than a `/nix/store` path, which would break
after garbage collection. It accepts Zed's JSON-with-comments format, refuses
unparseable settings, writes atomically, and keeps a timestamped backup of the
original file for every change. The rewritten file does not keep comments; they
remain in the backup. Rerunning it on configured settings changes nothing.

Repository guidance for Claude sessions lives in `CLAUDE.md`. Authentication
and `~/.claude` are mutable per-user state and do not belong in Nix or Git.

## Git and GitHub user state

Run these interactively as the user who will develop on Helix:

```bash
gh auth login
git lfs install
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

GitHub authentication, Git LFS filter setup, Git identity, extension state,
Codex login, Claude Code login, and Zed settings are mutable per-user state. NixOS installs the tools but should
not own those identities or credentials.

## Repository checks

Run the complete non-activating validation suite with:

```bash
./scripts/dev-shell.sh --run './scripts/check.sh'
```

The formatter, Deadnix, and Statix checks exclude only the generated
`hardware-configuration.nix`. Maintained modules remain fully checked, and the
formatter uses temporary copies without rewriting source files. The default suite
evaluates repository invariants against NixOS 26.05 without building; only
`--full` builds the canonical configuration and its closure checks. Checking and building do not
activate; dry activation previews changes, `test` changes the running system,
and `switch` also changes the persistent boot selection. Reboot and destructive
reinstall remain separate human actions.
