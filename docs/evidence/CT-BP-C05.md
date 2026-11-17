# CT-BP/C05 — Rising Water corrective development evidence

- Date: 17 November 2026.
- Base: merged C04 `main` commit `4d7fcd355a45cffa5c97201bc1a9a6984d5b21d8` (merged-main CI #44042394225 SUCCESS).
- Work branch: `task/CT-BP-C05-rising-water-fidelity`.
- Primary authority: Development Blueprint v1.0, pp.18–19; corrected source reconciliation.
- **Verification status at this evidence revision: NOT YET CI-QUALIFIED.** No unobserved test claims.

## Development changes

- GRID30, 14/14 west/east feeders, 13+12 required PU; GEN8 and 5+4 PU pumps.
- Two independent 120-continuous-tick pump access latches; both flooded GRID feeder trunks are initially broken and repaired as cable splices, not silently substituted west fuse faults; 9/8 concurrent overload remains unsafe; generator route order independent.
- Host-only first-accepted-pickup optional cold-store bonus: 1800 ticks, durable fail-closed conditional state, no hard failure; HUD reads authoritative remaining ticks.
- Complete 6-service solution trace and C05 negative/integration test replacement; earlier C05 provisional evidence retained without rewriting history.
- No deployed checkpoint migration, physical scene promotion, Steam publishing or save deletion.

## Mandatory gates

1. Correct Godot 4.7.2 parse/source failures, if any, observed on GitHub.
2. Exact PR-head **Linux + Windows** CI full suite, content validation, Python parity, all C01–C08 solution traces, Windows export/headless source pin.
3. Merge only after success and verify exact merged-main CI. Update this evidence with real run/commit receipts.
4. Leave physical Canal Yard generator/socket/water access presentation, HUD/controller/human, target GPU performance, old shipped C05 checkpoints, Steam two-network F02/F06 and original-blueprint production acceptance **HOLD**.

## Resume notes

Continue on this branch until the final exact-head CI is green, then merge and record the merged-main receipt. The next separate corrective phase is CT-BP/C06 with cumulative, non-resetting COLD_STORE outage timer. Do not assume C05 preview art or prior historical saves are production compatible.
