{
  lib,
  writeShellApplication,
  jq,
}:

writeShellApplication {
  name = "helix-zed-agent-setup";
  runtimeInputs = [ jq ];
  text = ''
    set -euo pipefail

    config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    settings_dir="$config_home/zed"
    settings_file="$settings_dir/settings.json"

    mkdir -p "$settings_dir"

    if [[ -e "$settings_file" ]]; then
      if ! jq empty "$settings_file" >/dev/null 2>&1; then
        printf 'Refusing to edit invalid JSON: %s\n' "$settings_file" >&2
        exit 1
      fi
      cp -a "$settings_file" "$settings_file.bak"
      current=$(cat "$settings_file")
    else
      current='{}'
    fi

    updated=$(jq '
      .agent_servers = ((.agent_servers // {}) + {
        "Claude Code": {
          "type": "custom",
          "command": "claude-agent-acp",
          "args": []
        },
        "Codex": {
          "type": "custom",
          "command": "codex-acp",
          "args": []
        }
      })
    ' <<<"$current")

    printf '%s\n' "$updated" > "$settings_file"
    printf 'Configured Claude Code and Codex ACP agents in %s\n' "$settings_file"
    if [[ -e "$settings_file.bak" ]]; then
      printf 'Previous settings backed up at %s\n' "$settings_file.bak"
    fi
  '';

  meta = {
    description = "Opt-in helper to register Nix-managed Claude and Codex ACP agents with Zed";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "helix-zed-agent-setup";
  };
}
