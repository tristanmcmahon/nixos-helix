#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.

printf 'Evaluating release, storage, desktop, security, and feature invariants...\n'
nix-instantiate --eval --strict tests/system-invariants.nix
nix-instantiate --eval --strict tests/monitoring-disabled.nix

printf 'Evaluating emulation enable/disable boundaries...\n'
nix-instantiate --eval --strict tests/emulation-disabled.nix
