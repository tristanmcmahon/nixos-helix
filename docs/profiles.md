# Package and profile boundaries

NixOS merges package lists contributed by ordinary imported modules. Package
modules contain software only; profiles compose those packages and own related
system policy.

## Enabled layers

### Base

`packages/base.nix` is imported directly and contains Git, curl, wget, `file`,
`tree`, and Vim as the guaranteed console recovery editor (`vi` and `vim`). It
deliberately excludes language runtimes, GPU tools, desktop conveniences,
gaming, and inference software.

### Workstation

`profiles/workstation.nix` imports daily interactive tools, hardware diagnostic
clients, and desktop media clients. Font policy is owned once by
`desktop/fonts.nix`. The profile contains no compiler toolchain or code
publishing tools.

### Development

`profiles/development.nix` is an explicit enable/disable boundary for editors,
GitHub publishing tools, Codex, compilers, runtimes, the Nix language server and
formatter, and ShellCheck. It remains separate even though it currently adds no
system service policy.

### Gaming

The enabled conservative gaming profile provides Steam, GameMode, MangoHud,
32-bit graphics, and 32-bit PipeWire/ALSA audio support. Steam owns its client
package and controller udev rules; it is not duplicated in the system package
list. Emulation remains outside this profile. Heroic, Lutris, Wine, Gamescope,
and custom Proton tooling have not been added.

The normal default dry build validates this active profile. Disabling the single
`./profiles/gaming.nix` import returns the evaluated configuration to the
non-gaming workstation layer.

### Local LLM

The enabled local-LLM profile selects the CUDA-enabled Ollama package for both
the service and user-facing CLI. Local inference is part of the normal default
system. The API binds only to `127.0.0.1`, and its firewall port remains closed.
Display-driver policy stays in `hardware/nvidia.nix`.

Models are stored at `/mnt/games_nvme/ollama/models`, outside the Steam library.
The service will not start unless GAMES_NVME is mounted and its narrowly scoped
initializer has created the model directory for the `ollama` service account.
Nix declares this baseline model set:

- `gemma4:12b` — fast/general local model
- `gpt-oss:20b` — stronger reasoning, agentic, and general work
- `qwen3.6:27b` — larger coding and reasoning model
- `qwen3-embedding:4b` — embeddings/retrieval, not conversational chat

The native NixOS `ollama-model-loader` starts after and binds to
`ollama.service`. It pulls every declared tag in parallel when the loader starts
and retries failed pulls with bounded backoff. Existing Ollama blobs and
manifests remain mutable data in the same model store; they never enter the Nix
store. `syncModels = false` means manually pulled experimental models are
preserved rather than treated as undeclared state to delete.

Update ownership remains deliberately simple:

- Ollama program updates come from a nixpkgs update and NixOS rebuild.
- Model tag updates come from `ollama pull`, including the native loader.
- Experimental models remain untouched because model syncing is disabled.

To deliberately refresh all four declared tags without waiting for the model
loader lifecycle, run the helper generated from the same canonical Nix list:

```bash
helix-ollama-update-models
```

The same native loader creates small aliases with model-specific context
defaults after reconciling their upstream models. Aliases reuse Ollama's
content-addressed blobs; they do not duplicate weights:

| Alias | Upstream model | Context | Measured residency before activation |
| --- | --- | ---: | --- |
| `helix-gemma` | `gemma4:12b` | 8192 | 100% GPU, about 8.7 GiB Ollama VRAM, about 78 tok/s |
| `helix-gpt-oss` | `gpt-oss:20b` | 8192 | 100% GPU, about 12.7 GiB Ollama VRAM, about 151 tok/s |
| `helix-qwen` | `qwen3.6:27b` | 4096 | 29% CPU / 71% GPU, about 13.2 GiB VRAM, about 7.9 tok/s |
| `helix-embedding` | `qwen3-embedding:4b` | 4096 | 100% GPU, about 4.5 GiB Ollama VRAM |

These are short cold-start measurements on the RTX 5080, not benchmark claims.
Reducing Qwen to 2048 left its split unchanged and slightly reduced throughput,
showing that its 17 GB weights—not the 4K context—cause the offload. It remains
useful for deliberate larger tasks but is not the everyday responsive model.

The service permits one loaded model and one parallel request at a time. This
avoids VRAM contention: GPT-OSS at 8K left only about 1.2 GiB free during the
measurement. Ollama's finite upstream five-minute keep-alive is retained; no
infinite lifetime is configured. There is deliberately no global context,
flash-attention, or quantised KV-cache override. The measured contexts already
meet the residency goal, and unmeasured global tuning would affect every model.

Normal operator inspection is available through either the native commands or
the concise snapshot helper:

```bash
helix-ollama-status
ollama list
ollama ps
```

After activation, repeat representative requests through the aliases and use
`ollama ps` plus `nvidia-smi` to confirm the generated profiles behave like the
measured upstream models. Successful evaluation alone does not prove that
inference is GPU-accelerated.
