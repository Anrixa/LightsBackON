# CT-BP/C06 — Cold Chain corrective development evidence

- Date: 17 November 2026.
- Base: verified main `5544eaed2c163420346b6d817d9f29b6a065d44f`; merged-main CI [#44047679775](https://github.com/Anrixa/LightsBackON/actions/runs/44047679775) SUCCESS.
- Work branch: `task/CT-BP-C06-cold-chain-cumulative-outage`.
- Authority: original Development Blueprint v1.0 pp.18,20 and recovered C06 reconciliation.
- Current gate: **PENDING** exact-head Linux + Windows CI and replay. Do not infer compliance from unrun code.

## Corrective implementation
- Replace eight provisional C06 content/solution JSON files with GRID30, GEN8, healthy west13, east12 broken, 4 PU pump with a 120-tick access latch, and exclusive COLD_STORE 5 PU TEMP/GRID paths.
- Host-only cumulative unsupplied timer, strict 1200-tick cutoff, safe supply rooted in approved GRID or GEN without overload, durable fail-closed restore and authoritative HUD readout.
- Replace provisional timer test suite with 11 boundary/host/negative/legacy checks and complete C06 host-intent replay. Preserve historical provisional receipts without rewriting their outcomes.
- No save deletions, no migration, no Steam changes.

## Required next gates
1. Run exact PR-head Linux + Windows GitHub Actions and resolve test/parse failures, if any.
2. Replay all C01–C08 traces, Python reference parity and Windows export/source-pin checks before merge.
3. Merge only after both OS jobs pass and independently verify merged-main CI; record exact receipts here.
4. Physical Canal Yard, real keyboard/controller/human and target GPU, old deployed C06 checkpoint compatibility, Steam F02/F06 and production acceptance remain **HOLD**.

## Resume notes
Commit and open PR for independently logged CI. This evidence explicitly reports source implementation without claiming unobserved test results.
