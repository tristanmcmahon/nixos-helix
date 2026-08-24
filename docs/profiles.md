# Package and profile boundaries

NixOS merges package and policy contributions from ordinary imported modules.
Packages stay close to the feature that needs them; profiles own the complete
feature boundary, including related service lifecycle when applicable.

## Base

`packages/default.nix` imports `packages/base.nix`, the deliberately small
always-present recovery set: Git, network/download tools, file/tree inspection
and Vim. Language runtimes, desktop conveniences, gaming and inference do not
belong here.

## Workstation

`profiles/workstation.nix` imports daily interactive tools, hardware diagnostic
clients and desktop media clients. Font policy is owned once by
`desktop/fonts.nix`.

## Development

`profiles/development.nix` owns editors, GitHub publishing tools, Codex,
compilers, runtimes, Nix development tools and ShellCheck. It remains a distinct
feature even though it currently adds no service policy.

## Gaming

`profiles/gaming.nix` owns Steam, GameMode, MangoHud and 32-bit graphics/audio
support. It also imports `services/hamsteam.nix`: hamSteam remains a separate
application checkout, while Helix owns the lifecycle of its quiet maintenance
service.

Emulation builds on gaming but remains a separate reversible feature.

## Emulation

`profiles/emulation.nix` exposes one public option:

```nix
helix.emulation.enable = true;
```

Its implementation is split into storage/preparation, metadata/DAT tooling and
launchers under `profiles/emulation/`. ROMs remain on the authoritative NAS
share and emulator state remains NAS-backed.

## Local LLM

`profiles/local-llm.nix` owns the CUDA-enabled Ollama service and CLI, the model
baseline, the model-refresh helper, and the OpenClaw gateway lifecycle. Ollama
binds only to `127.0.0.1` and its firewall port remains closed. Display-driver
policy stays in `hardware/nvidia.nix`.

Models live at `/mnt/games_nvme/ollama/models`, outside the Steam library. The
service depends on the narrowly scoped storage initializer for that path.

The declared baseline is:

- `deepseek-r1:8b`
- `gemma4:12b`
- `gpt-oss:20b`
- `qwen3.6:27b`
- `qwen3-embedding:4b`

`syncModels = false` preserves manually pulled experimental models. Refresh the
baseline deliberately with:

```bash
helix-ollama-update-models
```

Inspect live state with:

```bash
ollama list
ollama ps
nvidia-smi
```

Successful Nix evaluation proves configuration, not physical GPU execution.
