# Package and profile boundaries

NixOS merges package lists contributed by ordinary imported modules. Package
modules contain software only; profiles compose those packages and own related
system policy.

## Enabled layers

### Base

`packages/base.nix` is imported directly and contains only Git, curl, wget,
`file`, and `tree`. It deliberately excludes editors, language runtimes, GPU
tools, desktop conveniences, gaming, and inference software.

### Workstation

`profiles/workstation.nix` imports daily interactive tools, hardware diagnostic
clients, and a modest font set. It contains no compiler toolchain or code
publishing tools.

### Development

`profiles/development.nix` is an explicit enable/disable boundary for editors,
GitHub publishing tools, Codex, compilers, runtimes, the Nix language server and
formatter, and ShellCheck. It remains separate even though it currently adds no
system service policy.

## Dormant profiles

Enable an optional profile by uncommenting its import in `configuration.nix`,
then run `./scripts/check.sh` before `test`.

### Gaming

The conservative gaming profile enables NixOS Steam integration, 32-bit
graphics, 32-bit PipeWire/ALSA libraries, GameMode, and MangoHud. Steam owns its
client package and controller udev rules. The profile deliberately excludes
Lutris, Gamescope, Wine variants, Proton managers, emulators, firewall rules,
and extra controller daemons.

Validate it independently while it remains disabled:

```bash
./scripts/check-profile.sh gaming
```

### Local LLM

The local-LLM profile selects the CUDA-enabled Ollama package for both the
service and user-facing CLI. The API binds to `127.0.0.1`, and its firewall port
remains closed. Display-driver policy stays in `hardware/nvidia.nix`.

Ollama's NixOS defaults store models under `/var/lib/ollama/models`. Downloads
can consume substantial disk space; pulling and deleting models is runtime
state and is not declared during activation:

```bash
ollama pull MODEL
ollama rm MODEL
```

Validate the disabled profile with:

```bash
./scripts/check-profile.sh local-llm
```

After enabling and starting it, run a model and use `nvidia-smi` in another
terminal to verify actual GPU use. Successful evaluation alone does not prove
that inference is GPU-accelerated.
