# EXP02 — Level geometry and planned capacity evidence

## Baseline
EXP01 merged source c42f37bb097e9fdf4bd930ccff23e93dbdbfaa09.
Branch: task/EXP02-200-level-geometry.

## Implemented
- 200 source-derived unique candidate layout plans, 1,000 non-interactive named station markers and per-level safe/unsafe power-capacity plans.
- 3D graybox factory builds original geometry for all 200 locations on demand, with production data and saves isolated.
- In-game atlas shows an overhead 3D schematic of the selected level, one scene at a time.
- Godot regression cases for 200 plan uniqueness, numeric capacity trade-offs, 200 scene constructions, five stage pads and UI selection teardown.

## Evidence status
- EXP01 source/head CI Linux+Windows succeeded #44391460451 (773 tests, 55,208 assertions per OS).
- EXP02 exact PR-head Linux/Windows CI: **PENDING**.
- EXP02 merged-main independent CI / Windows QA57 export: **PENDING**.
- Actual contiguous human/controller walk, real cameras, render/GPU P95, Steam F02/F06, 200 host-backed task missions and production release: **OWNER HOLD**.

## Certification ceiling
No new 3D preview marker can be selected as an authoritative target or grant a reward. The layout is a real constructed scene, but not a verified traversable or playable level. No fabricated completion claims.

## Resume
Fix any engine/test failures on the final exact head, verify both OSes, merge normally and verify independent main CI. Next production step is EXP03 host-driven mission actions and 200-level state integration under a separate reviewable authority protocol.
