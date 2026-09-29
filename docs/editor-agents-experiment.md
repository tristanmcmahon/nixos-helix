# Editor agents experiment

Status: experimental. Do not merge this branch to `main` until it has passed
real Helix build and activation tests.

Scope:

- keep the existing Zed install;
- add the NixOS 26.05 Claude Code CLI;
- add the NixOS 26.05 Claude and Codex ACP adapters;
- package VS Code with the Nix IDE and Anthropic Claude Code extension;
- keep the existing Codex VS Code recommendation;
- configure Claude and Codex as project-local Zed External Agents.

Deliberately excluded:

- OpenClaw changes;
- Home Manager;
- global mutation of `~/.config/zed/settings.json`;
- credentials, tokens, or API keys;
- any merge to `main` before live validation.

Validation order on Helix:

```bash
./scripts/rebuild.sh dry-build
./scripts/rebuild.sh test
claude --version
claude doctor
codex --version
claude-agent-acp --help
codex-acp --help
code --list-extensions --show-versions
zed .
```

Only after the temporary `test` activation is healthy should this experiment
be considered for promotion to `main`.
