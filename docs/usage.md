# Everyday commands

This is the short operator surface. Deeper guides cover setup and recovery.

## Helix system

Validate and build without activating:

```bash
cd ~/Projects/nixos-helix
./scripts/rebuild.sh dry-build
```

Make the built configuration current:

```bash
./scripts/rebuild.sh switch
```

## hamLLM

```bash
hamllm doctor
hamllm models
hamllm run "your question"
hamllm chat
```

## Gwen

```bash
cd ~/Projects/hamGwen
make run
```

After a fresh clone or dependency update:

```bash
make deps
make build
```

## HamSidian

```bash
hamsidian review
hamsidian maintain
```

## hamSteam

Read-only plan:

```bash
cd ~/Projects/hamSteam
python hamsteam.py
```

Apply the freshly revalidated plan:

```bash
python hamsteam.py --apply
```

The quiet service is NixOS-owned:

```bash
systemctl --user status hamsteam-maintain.timer
journalctl --user -u hamsteam-maintain.service
```

## Local models

```bash
ollama list
helix-ollama-update-models
```

Use `ollama ps` and `nvidia-smi` when checking whether a live model is actually
using the GPU.
