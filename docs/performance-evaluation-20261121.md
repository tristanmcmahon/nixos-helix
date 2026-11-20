# Helix validation performance — 21 November 2026

## Hypothesis and boundaries

The original `scripts/checks/evaluation.sh` starts four separate
`nix-instantiate --eval --strict` processes for:

1. `tests/system-invariants.nix` (production)
2. `tests/monitoring-disabled.nix` (monitoring off)
3. `tests/emulation-disabled.nix` (emulation off)
4. `tests/features-disabled.nix` (all optional features off)

A single `tests/quick-evaluations.nix` process imports **the same four
test files and assertions**, without removing cases. This reduces evaluator
startup and permits Nix expression reuse. It changes only local/CI
validation; it does not modify the deployed NixOS configuration.

## Reproducible A/B test

Run `./scripts/dev-shell.sh --run 'python3 scripts/bench-evaluations.py --samples 3'`.
The probe warms both methods, alternates execution order between rounds,
requires every Nix evaluation to output `true`, times elapsed wall clock
and measures maximum per-process RSS using GNU time (KiB). It does not
activate a generation or run a full system build. The path-filtered
`Nix Evaluation Performance` CI workflow is available for later measurements
without increasing every unrelated PR's validation cost.

Results are *within-runner* measurements; the cold runner and Nixpkgs cache
state differ between GitHub Actions runs. Never compare single observations
from unrelated runners as if they were controlled experiments.

### Run 2: baseline versus one process (no RSS collected)

- Run: https://github.com/tristanmcmahon/nixos-helix/actions/runs/44826634101
- 3 warmed, alternating samples.
- Baseline: 10.2564 / 10.3429 / 10.1767 seconds; median **10.2564 s**.
- One process: 7.6784 / 7.7911 / 8.1732 seconds; median **7.7911 s**.
- Relative median elapsed change: **-24.04%**.

### Run 6: memory-cost challenge

- Run: https://github.com/tristanmcmahon/nixos-helix/actions/runs/44827249286
- 3 warmed, alternating samples.
- Baseline median: **9.8924 s**; peak Nix process RSS approximately 995,000 KiB.
- One-process median: **8.2460 s (-16.64%)**; RSS samples
  1,116,580 / 1,261,580 / 1,427,260 KiB.
- Verdict: a real memory cost, with variability between repeated invocations;
  do not call the speedup free.

### Run 8: three-method alternative check

- Run: https://github.com/tristanmcmahon/nixos-helix/actions/runs/44827734710
- 3 warmed, interleaved samples on the **same** Ubuntu runner.

| Approach | Median seconds | Approx. median peak Nix RSS | Speed change |
| --- | ---: | ---: | ---: |
| Four evaluators | 12.6687 | 1,003,976 KiB | baseline |
| Two evaluators | 10.8922 | 1,070,228 KiB | -14.02% |
| One evaluator | 9.5339 | 1,159,844 KiB | -24.74% |

## Decision

Keep the one-process path. On the representative three-way runner it saved
3.13 seconds at the cost of roughly 156 MiB of extra peak Nix process
memory. Even the higher observed run-6 memory peak was below 1.4 GiB.
This is a short-lived check, not a daemon; its consumption is proportionate
on Helix's 32 GiB workstation.

Do not infer lower boot time, higher game FPS, faster CUDA, or lower idle
power. None was measured here. If future CI or Helix measurements reveal an
unacceptable memory cost, the previous four-process evaluation remains
available in Git history, and the two-process experiment can be reconstructed
from benchmark run 8.

The **full production** rebuild, GPU benchmark, boot-to-session timeline and
NAS-offline recovery proof remain separate qualifications under
`docs/survivability-contract.md` and `docs/benchmarking.md`.
