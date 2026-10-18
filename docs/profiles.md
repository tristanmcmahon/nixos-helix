# Package and profile boundaries

Every module is imported unconditionally. Each optional feature is a profile
that declares a `helix.<feature>.enable` option and owns its packages, services
and storage initialisers; `configuration.nix` only chooses which are enabled:
`workstation`, `development`, `gaming`, `localLlm`, `emulation`, `hamCade` and
`monitoring`. `tests/features-disabled.nix` turns them all off and checks that
each one's packages, services and directories disappear while the recovery base
remains. `packages/` holds only package definitions and the base set.

## Enabled layers

### Base

`packages/base.nix` is imported directly and contains Git, curl, wget, `file`,
`tree`, `nix-output-monitor`, `nvd`, and Vim as the guaranteed console recovery editor (`vi` and `vim`). It
deliberately excludes language runtimes, GPU tools, desktop conveniences,
gaming, and inference software.

### Workstation

`profiles/workstation.nix` imports daily interactive tools, hardware diagnostic
clients, and desktop media clients. Font policy is owned once by
`desktop/fonts.nix`. The profile contains no compiler toolchain or code
publishing tools.

### Development

`profiles/development.nix` is an explicit enable/disable boundary for editors,
GitHub publishing tools, Codex, Claude Code and its Zed ACP adapter, compilers, runtimes, the Nix language server and
formatter, and ShellCheck. It remains separate even though it currently adds no
system service policy.

### Gaming

The enabled conservative gaming profile provides Steam, GameMode, MangoHud,
32-bit graphics, and 32-bit PipeWire/ALSA audio support. Steam owns its client
package and maintained controller udev rules, including DualSense raw-device
access; it is not duplicated in the system package list. The upstream
`hid_playstation` driver and explicit absence of xpadneo are hardware policy in
`hardware/controllers.nix`. Emulation remains outside this profile. Gamescope,
ProtonPlus, Protontricks, MangoHud, GOverlay, and the repository-owned Doom
tooling are present, as is Heroic for the GOG copies of Fallout 4 and Fallout
London; `helix-fallout-london-setup` points Heroic's install and prefix
directories at a data SSD (`--ssd a|b|c`, default `a`) and prints the
remaining in-Heroic steps. Lutris and a general Wine package remain absent.

Fallout 4 and Fallout London must share one Wine prefix. Heroic's install
dialog can silently reset a game's prefix to its own per-title default, so
confirm each game's Settings shows the same prefix path before its first
launch. umu-launcher downloads its required Steam Runtime container
(`steamrt3`/`steamrt4`) from Valve's `repo.steampowered.com` mirror on first
use; if that mirror ever serves a tarball that fails digest verification
against its own `SHA256SUMS` (an upstream inconsistency, not local
corruption) and a native Steam install already has the matching
`SteamLinuxRuntime_*` under its own `steamapps/common`, copy that directory
(excluding its `var/` scratch subdirectory) into
`~/.local/share/umu/<variant>/` with a `umu -> _v2-entry-point` symlink; umu
accepts it once its own `pv-verify` mtree check passes, with no download
needed. Fallout London specifically needs Proton-CachyOS-latest rather than
GE-Proton-latest: GE-Proton11-9's wine-staging 11.0 build deadlocks
(`ntdll` `loader_section`/`fls_section`) during F4SE's multi-threaded DLL
injection. Fallout London's own installer deploys its `plugins.txt` and a
merged `Fallout4.ini` archive list into the shared prefix on first successful
run; if an earlier launch crashed before that completed, New Game boots
vanilla Fallout 4 instead of London, and the fix is copying
`Fallout London/__AppData/Plugins.txt` and `Fallout London/__Config/Fallout4.ini`
into the prefix by hand (back up the existing `Fallout4.ini` first; leave
`Fallout4Prefs.ini` alone since it holds shared display settings).

STAR WARS: Galactic Racer (Steam appid 4078430) is pinned to Valve's Proton
Hotfix build by default, under which it dies silently after about two and a
half minutes: its EOS Bootstrapper's `CreateProcessAsUser` call fails under
Proton and falls back to a path that does not propagate the
`EOS_SESSION_GUID` environment variable to the second EOS helper process it
spawns (`EpicOnlineServicesUserHelper.exe --mode=stage`), which exits
immediately (`EOS_SESSION_GUID environment variable is required`, code 9001)
and leaves the game waiting on an online-services handshake that never
completes; its own log directory never gets created. Overriding the
compatibility tool to GE-Proton (Steam's Properties > Compatibility, or
ProtonPlus) gets past that handshake, but the title then hits an NVIDIA Xid
109 (`CTX SWITCH TIMEOUT`) within the first minute under both Proton Hotfix
and GE-Proton11-9: the process, audio and EOS overlay stay alive and the GPU
stays non-idle, but only the clear colour is ever presented, with no further
draw calls landing. Neither `PROTON_ENABLE_NVAPI=0` nor forcing ray tracing
off (`-noraytracing -execcmds="r.RayTracing 0"`) avoided it. The title is
confirmed working on Windows; unresolved on Helix as of 2026-10-18.

Setting `helix.gaming.enable = false` returns the configuration to the
non-gaming workstation layer; emulation asserts that gaming is enabled.

### Emulation and hamCade

`profiles/emulation.nix` owns console emulation only: PS2, PS3, PS4 and SNES
integration, the read-only console ROM automount and mutable console state below
`/mnt/games_nvme/emulation`.

Arcade is intentionally excluded. `hamCade` is the sole owner of MAME/libretro
arcade policy, ES-DE, DAT/audit logic, curation, artwork and arcade state. The
separately developed checkout remains at `/home/tristan/Projects/hamCade`.
`profiles/hamcade.nix` is only a thin Helix adapter that supplies the launcher
and pinned runtime packages. Its vendored dependency snapshot exists so NixOS
evaluation and CI do not require credentials for the private sibling checkout.

### Local LLM

The enabled local-LLM profile selects the CUDA-enabled Ollama package for both
the service and user-facing CLI. Local inference is part of the normal default
system. The API binds only to `127.0.0.1`, and its firewall port remains closed.
Display-driver policy stays in `hardware/nvidia.nix`.

Models are stored at `/mnt/games_nvme/ollama/models`, outside the Steam library.
The service will not start unless GAMES_NVME is mounted and its narrowly scoped
initializer has created the model directory for the `ollama` service account.
Nix declares this baseline model set:

- `deepseek-r1:8b` — compact reasoning model
- `gemma4:12b` — fast/general local model
- `gpt-oss:20b` — stronger reasoning, agentic, and general work
- `qwen3.6:27b` — larger coding and reasoning model
- `qwen3-embedding:4b` — embeddings/retrieval, not conversational chat

The native NixOS `ollama-model-loader` starts after and binds to
`ollama.service`. It pulls every declared tag in parallel when the loader starts
and retries failed pulls with bounded backoff. It stays active after a
successful run, so pulls happen once per boot or Ollama restart rather than on
every rebuild. Existing Ollama blobs and
manifests remain mutable data in the same model store; they never enter the Nix
store. `syncModels = false` means manually pulled experimental models are
preserved rather than treated as undeclared state to delete.

Update ownership remains deliberately simple:

- Ollama program updates come from a nixpkgs update and NixOS rebuild.
- Model tag updates come from `ollama pull`, including the native loader.
- Experimental models remain untouched because model syncing is disabled.

To deliberately refresh all five declared tags without waiting for the model
loader lifecycle, run the helper generated from the same canonical Nix list:

```bash
helix-ollama-update-models
```

Normal operator inspection remains:

```bash
ollama list
ollama ps
```

After activation, run a representative model and use `ollama ps` plus `nvidia-smi` in another terminal
to verify actual GPU use. Successful evaluation alone does not prove that
inference is GPU-accelerated. Helix sets `OLLAMA_CONTEXT_LENGTH=32768` for the
service, with flash attention (`OLLAMA_FLASH_ATTENTION=1`) and an 8-bit KV
cache (`OLLAMA_KV_CACHE_TYPE=q8_0`). At that context length the cache is a large
share of the 16 GB of VRAM; halving it keeps more of each model on the GPU.
Compare `ollama ps` (the GPU/CPU split) before and after a model loads to see
the effect. Keep-alive policy remains at the Ollama default.
