# CT-BP/C02 — Dinner Rush original blueprint corrective implementation

- Authority: canonical `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf` pp.18–19 (C01 baseline + C02 contract sheet).
- Baseline main `4d40b8a47d234fb92463fd5af456fe64f17b1987`; branch `task/CTL-BP-C02-dinner-rush-correction`.
- ADR-017 independent logic/data correction track. Original C02 logic CI from PR #156 is historical and remains valid **for the old provisional source only**.
- Certification: **HOLD_PENDING_FINAL_SOURCE_CI**, and physical/UX/release acceptance separately HOLD. Do not mark the official `docs/backlog.json` CT03 DONE.

## Specification applied

C02 starts with two separate faults: JW fuse failed/tripped, east `E_GRID_JE` broken. Original Alder GRID capacity24, west9/12 and east11/12, required total20. Optional SIGN training load3 is present but disabled and excluded from optional-service scoring, unlike the superseded provisional interpretation of C02. Portable GEN capacity6 can power MARKET5 or PUB4, not both for 10 seconds. Authored separate `E_TEMP_MARKET` and `E_TEMP_PUB` routes live at the logical `PAD_VENUES` only, with PowerGrid's existing atomic dual-supply check. This is **not** a physical pad location or scene certification.

`mission.json` now declares `opening_venues`: MARKET and PUB must EACH accumulate **100 consecutive supplied host ticks** from a valid non-overloaded GRID or GEN source, before/on relative elapsed tick1800 (180 seconds). The clock is started **only by `SessionHost.begin_after_briefing()`**, a host-only method which validates at least one admitted player and all admitted players snapshot-synced. The headless solution harness calls this after all admissions/acknowledgments, explicitly modeling the deferred briefing dismissal. Real C02 scene gameplay will require this hook after its actual UI briefing/loading transition (C02 scene is not yet present). Extra `begin_after_briefing` calls are idempotent and do not extend the deadline.

Each venue's counter resets on any supply loss, including off/on within one 10Hz tick, until it latches. Latches remain granted after later loss, and a missed deadline emits a durable host-state failure and `opening_deadline_missed` event once. The miss never cancels required repairs, verification or extraction. Full completion earns 3 stars if both venue latches succeed and no preventable trips occur; otherwise (no trips) 2 stars. The result contains two independent optional venue names, not a SIGN first-supply record.

## Verified path, falsification and safe persistence

The 54-step solution supplies PUB4 temporarily for 100 ticks, repairs JW and supplies MARKET5 for 100 ticks, stops and disconnects temporary PUB before repairing JE, stows the generator, verifies all five required GRID services for 100 ticks and extracts after 50 ticks. Expected final GRID total20/24, JW9/12, JE11/12, GEN off.

The newly rewritten `tests/integration/test_CTL1_C02_dinner_rush.gd` covers 16 original-sheet acceptance/negative cases: full host trace, explicit delayed clock start, exact 100-tick latches, same-tick dropout, exact 1800 boundary and missed deadline, GEN9/6 overload, wrong cable pad, dual-source atomic refusal, invalid authoring, tampered durable state, two-player extraction, and unchanged C01 save shape.

The new `opening_venues` persistent receipt is **conditional only for C02** with started flag, relative elapsed time, exact progress/latch dictionaries and failure boolean. The validator rejects malformed or invented values before partial restore. Legacy C01 and other contract snapshot shapes remain unchanged; C02 rule revision necessarily changes, and earlier deployed C02 checkpoints are **not automatically migrated or deleted**. A documented versioned compatibility policy is required before resuming older C02 sessions in a released build.

## Initial hosted CI finding and corrective test revision

- [CI #44002529243](https://github.com/Anrixa/LightsBackON/actions/runs/44002529243) on initial PR head `f65752d4a4d0a720a5202ee4ae3fe5262b7d0ba5`: Windows reported 645 passed/1 failed. The single C02 durable partial-progress test expected MARKET=50 despite the trace runner already advancing one tick after the successful west feeder restore; actual authoritative progress=51, followed by the test's requested 50 more ticks. C02's 54-step solution replay solved in 395 ticks. This is an off-by-one test expectation, not evidence of power-supply failure.
- The assertion is corrected to 51. This revision **requires new final-head Linux/Windows CI** before source fidelity may advance. Preserve original CI logs.

## Pending acceptance

1. Exact PR head: full Linux and Windows checks, host trace replay C01–C08, Python reference parity, Godot parsing and Windows export/QA57.
2. Physical/UX: playable C02 scene, authored vendor sockets and generator handling, clock feedback accessibility, controller and human measurements, target GPU P95/memory. Do **not** infer these from headless CI.
3. Steam two-network F02/F06, V09/D08 human gates, and canonical CT03/CT04/CT05 dependencies remain independent.

The next corrective workstream after C02 headless merge is CT-BP/C03 Roof Route (west-fed 50-tick ladder access and optional 2PU/100-tick roof work light), followed by C04, C05 and C06. Original-blueprint certification for those contracts remains HOLD.
