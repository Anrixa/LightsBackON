# CT-L3/C12 — Lights Back On

- Source authority: Development Blueprint v1.0 pp.18,20–21 and `docs/design/CTL3-C10-C12-blueprint-spec.md`.
- Baseline: merged C11 `b29a68c0b5255b71febb2520353c836aeb51d622`. Independent branch: `task/CTL3-C12-lights-back-on`.
- Status: **SOURCE_IMPLEMENTED_UNVERIFIED**. PR-head and merged-main CI are mandatory before source qualification.
- Hill GRID28, WEST/EAST14, GEN6, WEST failed fuse, EAST broken feeder.
- GEN4 DRAIN_CONTROL for 120 uninterrupted host ticks unlocks east repair. Generator is returned to the van before final extraction.
- Required grid supply WEST13 + EAST12 =25. Optional BEACON3 via direct installed GRID→BEACON_SPUR4, final GRID28/28; unsafe WEST16/14 cannot count for bonus.
- Beacon optional reward requires 100 continuous safe GRID ticks; missed optional must not block extraction.
- Conditional host-only verification finale: deterministic wave cues over 20 ticks and short radio subtitle; no input lock, no fake physical animation claim. Results offer replay and remaining optional tasks.
- C01–C11 save shapes unchanged. C12 checkpoint must be strict and fail-closed.

**Required gates:** exact final PR-head CI Linux+Windows, C01–C12 solution replay, content validator, cross-language reference, Windows EXE/PCK QA57 and independent merged-main dual-OS CI. Any failing test requires correction and re-run before merge.

**HOLD:** physically authored Hill Road level, staged light placement and animation, actual accessible radio presentation, real controller/human gameplay, target GPU measurements, historical deployed checkpoint restore, Steam F02/F06 and canonical CT02/CT05/CT06/release.

## First exact-head CI diagnosis (retained, not a pass)

First PR-head run [#44154807880](https://github.com/Anrixa/LightsBackON/actions/runs/44154807880), source `8d5fa820cc252694877a7bad9bc77f8f579b1a74`: Linux **FAIL**: 710 tests passed, 2 tests failed; C01–C12 solution traces SOLVED (C12 353 ticks, 70 steps). Root cause: C12 conditional `finale` receipt inserted twice into `canonical_state` and omitted from `durable_state` (a checkpoint and HUD projection regression); also C12 tests counted normal pacing ticks twice at precise 119/120 and 0/10/20 boundaries. Corrected the actual projection and made tests count initial consumed ticks explicitly. Updated source must pass fresh exact-head Linux/Windows CI before any merge.
