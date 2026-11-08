#!/usr/bin/env python3
"""Register the Helix-managed Claude Code ACP agent in Zed user settings.

This helper owns only the existing Claude Code agent entry. As part of removing
the failed Helix OpenClaw ACP integration, it also deletes that exact legacy
managed entry when present. Generic MCP client configuration belongs outside
nixos-helix.
"""

import datetime
import json
import os
import pathlib
import sys
import tempfile

AGENTS = {
    "Claude Code": {"type": "custom", "command": "claude-agent-acp", "args": []},
}

LEGACY_OPENCLAW_ACP = {
    "type": "custom",
    "command": "helix-openclaw-acp",
    "args": [],
}


def strip_jsonc(text):
    """Remove comments and trailing commas outside JSON strings."""
    output = []
    index = 0
    length = len(text)
    in_string = False
    while index < length:
        character = text[index]
        if in_string:
            output.append(character)
            if character == "\\" and index + 1 < length:
                output.append(text[index + 1])
                index += 2
                continue
            if character == '"':
                in_string = False
            index += 1
        elif character == '"':
            in_string = True
            output.append(character)
            index += 1
        elif text.startswith("//", index):
            newline = text.find("\n", index)
            index = length if newline == -1 else newline
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            if end == -1:
                raise ValueError("unterminated block comment")
            index = end + 2
        elif character == ",":
            lookahead = index + 1
            while lookahead < length and text[lookahead] in " \t\r\n":
                lookahead += 1
            if lookahead < length and text[lookahead] in "}]":
                index += 1
            else:
                output.append(character)
                index += 1
        else:
            output.append(character)
            index += 1
    return "".join(output)


def configure(settings_file):
    settings_file.parent.mkdir(parents=True, exist_ok=True)
    backup = None
    settings = {}
    if settings_file.exists():
        original = settings_file.read_text(encoding="utf-8")
        if original.strip():
            try:
                settings = json.loads(strip_jsonc(original))
            except ValueError as error:
                raise SystemExit(f"Refusing to edit unparseable settings {settings_file}: {error}")
        if not isinstance(settings, dict):
            raise SystemExit(f"Refusing to edit non-object settings: {settings_file}")
        servers = settings.get("agent_servers", {})
        if not isinstance(servers, dict):
            raise SystemExit(f"Refusing to replace non-object agent_servers in {settings_file}")
        legacy_absent = servers.get("OpenClaw ACP") != LEGACY_OPENCLAW_ACP
        if all(servers.get(name) == agent for name, agent in AGENTS.items()) and legacy_absent:
            print(f"Helix Claude Code agent is already configured in {settings_file}")
            return None
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup = settings_file.with_name(f"{settings_file.name}.{stamp}.bak")
        counter = 1
        while backup.exists():
            backup = settings_file.with_name(f"{settings_file.name}.{stamp}-{counter}.bak")
            counter += 1
        backup.write_text(original, encoding="utf-8")

    servers = settings.setdefault("agent_servers", {})
    if servers.get("OpenClaw ACP") == LEGACY_OPENCLAW_ACP:
        del servers["OpenClaw ACP"]
    for name, agent in AGENTS.items():
        servers[name] = agent
    descriptor, temporary = tempfile.mkstemp(dir=settings_file.parent, prefix=".settings.", suffix=".json")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(settings, handle, indent=2)
            handle.write("\n")
        if settings_file.exists():
            os.chmod(temporary, settings_file.stat().st_mode & 0o777)
        os.replace(temporary, settings_file)
    except BaseException:
        pathlib.Path(temporary).unlink(missing_ok=True)
        raise

    print(f"Configured {', '.join(AGENTS)} in {settings_file}")
    if backup is not None:
        print(f"Previous settings backed up at {backup} (comments are kept only there)")
    return backup


def main(argv):
    if len(argv) == 2 and argv[1] in ("--help", "-h"):
        print("Usage: helix-zed-agent-setup")
        print("Register Claude Code in Zed and remove the exact legacy Helix OpenClaw ACP entry if present.")
        return 0
    if len(argv) > 1:
        print("Usage: helix-zed-agent-setup (takes no arguments; see --help)", file=sys.stderr)
        return 2
    config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.environ["HOME"], ".config")
    configure(pathlib.Path(config_home) / "zed" / "settings.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
