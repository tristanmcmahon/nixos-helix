#!/usr/bin/env bash

# Sourced by scripts/check.sh; shares its strict mode and validation context.
# Batching the same four invariant files into one Nix interpreter preserves
# every assertion and feature-disable boundary while avoiding three full
# evaluator process startups (measured in CI, see docs/benchmarking.md).

printf 'Evaluating release, storage, desktop, security, and feature invariants...\n'
printf 'Evaluating monitoring-off, emulation-off and all-features-off boundaries...\n'
nix-instantiate --eval --strict tests/quick-evaluations.nix
