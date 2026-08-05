# Alpha 3 historical release notes

This file is historical context, not current operating guidance.

Alpha 3 adds Spotify, VLC, mpv, Haruna, Strawberry, Plex Desktop, and a native
GridPlayer package, plus Signal Desktop and Pidgin. It also enables the
1Password GUI and CLI, managed extension
policies for Chrome, Chromium, and Firefox, Zen browser allowlisting, and
documented opt-in SSH-agent preparation.

Ollama local inference is enabled by default with its CUDA package. Its API
listens only on `127.0.0.1`, and no firewall port is opened. Models are runtime
data selected and downloaded manually; they are not installed declaratively.

A future release may be marked after runtime validation with:

```bash
git tag -a v0.3.0-alpha.3 -m "Helix NixOS Alpha 3"
```
