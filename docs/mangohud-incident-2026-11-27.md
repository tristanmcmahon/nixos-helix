# Steam / MangoHud launch regression — 27 November 2026

## User-visible impact

Optional OpenGL FPS recording work interfered with Helix's primary purpose:
launching and playing games. On a new generation Noita failed to launch,
and after a rollback to generation 76 plus a reboot Steam reported Noita
as running without a visible Noita window. The user spent the evening
restarting Steam, rolling back and rebooting. This was unacceptable for
an optional benchmark feature.

## Timeline and directly observed evidence

- Generation 75, installed 27 November at 16:22, predates PR #141.
  The user later explicitly switched to generation 75, rebooted, and
  confirmed that Noita worked.
- PR #140 introduced automatic Steam-scoped MangoHud logging for Vulkan.
  Space Marine 2 and Tekken 7 produced dated CSVs on 27 November.
- PR #141 added Steam-wide `extraProfile` exports of
  `LD_PRELOAD=libMangoHud_shim.so` and 32/64-bit MangoHud
  `LD_LIBRARY_PATH`. Noita received `MANGOHUD=1` and
  `MANGOHUD_CONFIG`, but had no MangoHud library mapped and did not
  record automatically. The owner confirmed that a manual
  `mangohud %command%` launch option *did* work.
- A later process inspection showed `LD_PRELOAD=libMangoHud_shim.so`
  in the Steam environment, and pressure-vessel commands with both
  64-bit and 32-bit MangoHud shims explicitly preloaded. Earlier claims
  that the FHS profile never executed were contradicted by this evidence.
- PR #142 then used `STEAM_GAME_LAUNCH_SHELL` to wrap every game command
  in MangoHud and was merged after green CI, **without live
  verification**. Noita stopped launching after deployment.
- PR #143 reverted #142. Rolling back from generation 77 to generation
  76 did not recover Noita: Steam's game-launch chain remained active
  without a visible game window after reboot.
- Switching explicitly to generation 75 and rebooting restored Noita.
  This is strong evidence that the newer Steam instrumentation was
  responsible, although no isolated controlled experiment apportioned
  the failure between the two changes.

## Failure of the engineering process

- Steam startup and per-game launch integration was changed for an optional
  improvement without a live test of the candidate before merge.
- Passing static checks, Nix evaluation and system closure builds was
  presented as if it established game launch compatibility. It did not.
- Conflicting evidence about whether the FHS profile executed was promoted
  to a confident root-cause claim, encouraging a second intrusive attempt.
- The repository remained vulnerable to re-deploying defective code
  after local rollback; source repair was not completed first.
- The scope and risk of the change were disproportionate to the feature.

## Containment and policy

- Remove PR #141's Steam-wide loader overrides while preserving its
  independent benchmark CSV reader improvements.
- Keep PR #143's earlier revert of #142.
- Preserve Steam-scoped Vulkan recording from #140.
- Do not implement automatic OpenGL injection until a branch-isolated
  candidate has passed owner-authorised live testing: Steam opens,
  Noita displays and plays, Tekken 7 or Space Marine 2 displays and
  plays, and fresh per-game CSVs show no regression. A claimed
  automatic Noita capture must work without a manual launch option.
- Roll back immediately if a game stops launching, and do not merge
  unverified follow-up fixes. An incomplete optional feature is
  preferable to compromising the computer.

This record is about evidence and operating rules, not a claim that a
new automatic OpenGL solution has been found.
