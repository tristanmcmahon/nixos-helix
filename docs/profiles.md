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
Pulling and deleting models remains runtime state and is not declared during
activation:

```bash
ollama pull MODEL
ollama rm MODEL
```

After activation, run a model and use `nvidia-smi` in another
terminal to verify actual GPU use. Successful evaluation alone does not prove
that inference is GPU-accelerated.
