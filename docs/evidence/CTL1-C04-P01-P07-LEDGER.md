# CT-L1/C04 P01–P07 — source/headless engineering evidence ledger

**Scope:** source and Godot headless qualification of the **C04 The Whole Block** unsaved preview. The independent original-blueprint specification is `docs/design/CT-BP-C04-original-blueprint-spec.md`. This ledger is a cumulative source-level handoff, **not** certification of physical gameplay, route continuity or release readiness.

## Phase receipts (immutable historical order)

| Phase | Change boundary | Primary evidence | GitHub PR |
| --- | --- | --- | --- |
| P01 | Dedicated 4-PU GRID→SPUR sign preview, original C04 topology and explicit no-save boundary | [P01](CTL1-C04-P01.md) | [#179](https://github.com/Anrixa/LightsBackON/pull/179) |
| P02 | Host-bound JE repair at street panel, isolated sign feeder, staged switch/sign continuity and extraction replay | [P02](CTL1-C04-P02.md) | [#180](https://github.com/Anrixa/LightsBackON/pull/180) |
| P03 | Host-only state projection, source-specific sign-bonus latch, contract-specific tablet identity | [P03](CTL1-C04-P03.md) | [#181](https://github.com/Anrixa/LightsBackON/pull/181) |
| P04 | All eight worksite plates, marker source validation and noncolliding station presentation | [P04](CTL1-C04-P04.md) | [#182](https://github.com/Anrixa/LightsBackON/pull/182) |
| P05 | Six neutral guidance cues at authored standing locations; compatibility-safe storage outside the hashed rules tree | [P05](CTL1-C04-P05.md) | [#183](https://github.com/Anrixa/LightsBackON/pull/183) |
| P06 | Read-only capsule, scene-marker, collider, sightline and target audits for eight stations; true JW cabinet obstruction | [P06](CTL1-C04-P06.md) | [#184](https://github.com/Anrixa/LightsBackON/pull/184) |
| P07 | Read-only eight-target near/far distance + facing-away reticle matrix, real callback regression, both cabinet occlusions, evidence consolidation | [P07](CTL1-C04-P07.md) | This branch's review/CI receipt |

## Previously independently verified merged-main checkpoints

- **P04:** main `2ca4cc94e5d818f7c8e243c311834418d29b2a19`; [Linux + Windows CI #44342287137](https://github.com/Anrixa/LightsBackON/actions/runs/44342287137) **SUCCESS**, 743 Godot tests and 53,337 assertions on each platform.
- **P05:** main `e95e67231f5c6ae174ec4d5c9072659da06e5235`; [Linux + Windows CI #44352298619](https://github.com/Anrixa/LightsBackON/actions/runs/44352298619) **SUCCESS**, 750 Godot tests and 53,466 assertions per platform, Windows QA57 export/smoke.
- **P06:** main `7e7f5705679436f7a3584752809f93e531e2ff6e`; [Linux + Windows CI #44374348957](https://github.com/Anrixa/LightsBackON/actions/runs/44374348957) **SUCCESS**, 758 Godot tests and 53,577 assertions per platform, all 12 contract solution replays and Windows QA57 export/smoke.
- Earlier P01–P03 work is cited by its phase-specific evidence and merged PR. No independent workflow numbers are invented here.
- **P07:** source change, head CI, merge and independent merged-main certification must be recorded with verified live CI results. The ledger alone does **not** pass a gate.

## Source-fidelity controls retained

1. C04 requires five GRID services (20/24 PU), with a separately optional SIGN (3 PU) fed through the **4 PU independent GRID-SPUR edge**; the hazardous east-sign branch remains isolated.
2. The west fuse and east trunk use meter/lock/repair host state machines; optional sign supply latches after 100 valid consecutive host ticks. No HUD, preview plate, guide or boundary audit can grant that latch.
3. Existing source-owned target positions and physics interaction callbacks retain authority. The test-only staged points are not a route/navmesh or evidence of movement continuity.
4. C01 production saves/configuration, C03 preview, original Alder colliders, host rules and `content/` rules hashes must not be altered by P07. `scenes/mission/c04_preview_approaches.json` remains outside `content/`; localization-only keys are covered by the existing presentation-only compatibility list.
5. Source tests and solution traces do not substitute for actual path traversal, real camera/UX testing or real GPU profiling.

## Explicit gates and handoff

| Gate | Current scope |
| --- | --- |
| P01–P06 source/headless CI | Verified on previously merged source checkpoints as documented above; P01–P03 receipts linked individually |
| P07 PR-head Linux+Windows suite and C01–C12 replays | **PENDING live CI** |
| P07 independent merged-main Linux+Windows / QA57 release export | **PENDING live CI** |
| Human/controller continuous walkway, route clearance under movement and readability | **HOLD — NOT TESTED** |
| Real target-GPU P95/VRAM, Steam F02/F06 multiplayer, production acceptance | **HOLD — NOT TESTED** |

**Conservative decision:** a green P07 source matrix qualifies only its discrete interaction boundary probes and nonmutation assertions. No accumulated static or staged tests silently lift any owner's physical playability or release hold.
