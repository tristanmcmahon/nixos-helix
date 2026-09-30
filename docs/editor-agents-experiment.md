# Editor agents experiment

Status: experimental. Do not merge this branch to `main` until it has passed
real Helix build and activation tests.

Scope:

- keep the existing Zed install;
- add the NixOS 26.05 Claude Code CLI;
- add the NixOS 26.05 Claude ACP adapter;
- pin Codex ACP 1.12.0 from agentclientprotocol because the NixOS 26.05
  codex-acp 0.13.0 package fails to link its embedded Bubblewrap sandbox on
  Helix;
- package VS Code with the Nix IDE and Anthropic Claude Code extension;
- keep the existing Codex VS Code recommendation;
- provide an opt-in helper that registers the Nix-managed Claude and Codex
  ACP binaries in Zed's user settings. Zed does not currently accept
  `agent_servers` in project-local `.zed/settings.json`.

Deliberately excluded:

- OpenClaw changes;
- Home Manager;
- automatic mutation of `~/.config/zed/settings.json`; the user must run
  `helix-zed-agent-setup` explicitly, and the helper backs up an existing
  settings file before changing only `agent_servers`;
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
codex-acp --version
code --list-extensions --show-versions
zed .
```

Only after the temporary `test` activation is healthy should this experiment
be considered for promotion to `main`.
