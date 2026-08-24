# Helix architecture

Helix is one ordinary NixOS configuration with explicit ownership boundaries.
`configuration.nix` composes those boundaries; it should not grow a catalogue of
implementation files.

## Layers

- `hardware/default.nix` owns device and driver policy.
- `desktop/default.nix` owns graphical sessions, applications, browsers and appearance.
- `shell/default.nix` owns the interactive shell environment.
- `system/default.nix` owns boot, users, networking, NAS and local storage.
- `services/default.nix` owns only cross-cutting machine services.
- `profiles/default.nix` composes optional functional features.
- `packages/default.nix` owns only the small always-present recovery package set.

`hardware-configuration.nix` remains generated machine evidence rather than
maintained policy. `config/host.nix` is pure data for the primary user, home and
project root; it is not a NixOS module or a second configuration framework.

## Feature ownership

A feature owns its packages, policy and lifecycle together:

- `profiles/gaming.nix` owns gaming policy and imports the hamSteam service lifecycle.
- `profiles/local-llm.nix` owns Ollama and imports the OpenClaw gateway lifecycle.
- `profiles/emulation.nix` owns the single `helix.emulation.enable` boundary.

Emulation keeps one public switch but separates its implementation:

- `profiles/emulation/storage.nix` — NAS validation, discovery and preparation.
- `profiles/emulation/metadata.nix` — DAT indexing, ROM audit and artwork/metadata tooling.
- `profiles/emulation/launchers.nix` — NAS-state launch wrappers and desktop entries.

Disabling a feature should remove its feature-specific service integration too.
Cross-cutting services such as SSH and Nix maintenance remain under
`services/default.nix`.

## Ham boundary

The Ham repositories remain applications, not subtrees of this NixOS repo.
Helix may own machine integration such as a systemd lifecycle, mount, package or
runtime prerequisite, but application behaviour stays in the application repo.

In particular:

- hamSteam owns Steam-library policy; Helix owns when its quiet maintainer runs.
- hamLLM owns reusable local-AI transport and agent mechanics; Helix owns Ollama.
- hamGwen owns Gwen-specific tools, prompts, approvals and behavioural policy.
- HamSidian owns vault review/maintenance and its local-data safety boundary.

Avoid copying application logic into Nix modules just to make installation look
uniform.

## Change rule

Add a new implementation file beneath the layer or feature that owns it, then
import it from that layer's entrypoint. Add a new top-level import to
`configuration.nix` only when introducing a genuinely new ownership boundary.

`scripts/check-modules.py` recursively verifies that maintained Nix modules are
reachable and are not imported through multiple owners.
