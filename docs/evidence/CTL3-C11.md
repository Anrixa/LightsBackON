# CT-L3/C11 — Borrowed Power source-development checkpoint

Authority: Original Development Blueprint v1.0 pp.18,20–21 and `docs/design/CTL3-C10-C12-blueprint-spec.md`.

Baseline: C10 merged main `7eda69f1b80863d5f82a0cab928d526251b051b1`. Branch: `task/CTL3-C11-borrowed-power`.

State: **SOURCE_IMPLEMENTATION_IN_PROGRESS; CI_NOT_VERIFIED.** Physical gameplay and release gates HOLD.

## Authored source contract
- Hill GRID28, WEST/EAST 14 PU, GEN6. West13 online, broken east12 trunk.
- GEN temporary exclusive telecom4/garage-control4. Both at once are 8/6 and unsafe.
- Shed greenhouse3, WEST10; WEST alternate telecom4 gives 14/14.
- Garage-control4 from GEN continuously for 100 host ticks grants east repair access.
- Repair east trunk with isolation, restore telecom to east GRID and greenhouse to west.
- Bonus: no valid telecom interruption above 50 consecutive host ticks, including initial darkness. The score is optional; core restoration remains possible.
- No legacy C01–C10 durable mission-shape mutation.

## Mandatory acceptance before merging
1. Exact PR head Linux and Windows CI successful; content, reference parity, C01–C11 host replay.
2. Negative tests for both generator loads, break-before-make, WEST feeder overload, outage 50/51, malformed saves and definitions, and legacy checkpoints.
3. Windows EXE/PCK release export and QA57 headless smoke.
4. Independent merged-main Linux and Windows CI.

Physical Hill scene, human/controller, target GPU, historical released save restore, Steam F02/F06, canonical CT06 and production remain HOLD. This document is not a certificate.

## First CI diagnosis — 17 November 2026 (UTC)

[GitHub Actions #44150472928](https://github.com/Anrixa/LightsBackON/actions/runs/44150472928), source `06e10fa3e2a85471dea617c093238f05e0d1ee3c`: Linux **FAILED** (695 passed, 4 failed). The invalid `PANEL_GARAGE_CONTROL` targeted a consumer, while meter panels require a source/junction; meter initialization refused the full panel map, so the linked east repair could not register. The 4 failing tests were downstream of that invalid content and two JSON numeric type comparisons. This is retained as a real failure receipt, not overwritten by a later success. Corrected by removing only that invalid consumer panel (the real `PANEL_EAST` remains) and normalizing the test JSON numeric assertions. Re-run exact changed head on both OS before promotion.

## Verified final-head and independent merged-main source CI — 17 November 2026 (UTC)

C11: [174](https://github.com/Anrixa/LightsBackON/pull/174) final source [CI #44151282829](https://github.com/Anrixa/LightsBackON/actions/runs/44151282829) SUCCESS Linux+Windows; merged-main `b29a68c0b5255b71febb2520353c836aeb51d622` [CI #44152056131](https://github.com/Anrixa/LightsBackON/actions/runs/44152056131) SUCCESS Linux+Windows. Source/headless only; original physical/Hill controller/GPU/old saves/Steam/release HOLD. Historical pending notes above are retained as original checkpoints.
