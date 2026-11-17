# CT-BP/C06 — Cold Chain corrective development evidence

- Date: 17 November 2026.
- Base: verified main `5544eaed2c163420346b6d817d9f29b6a065d44f`; merged-main CI [#44047679775](https://github.com/Anrixa/LightsBackON/actions/runs/44047679775) SUCCESS.
- Work branch: `task/CT-BP-C06-cold-chain-cumulative-outage`.
- Authority: original Development Blueprint v1.0 pp.18,20 and recovered C06 reconciliation.
- Source-aligned headless gate: **PASS** Linux/Windows exact PR head `5c4ede08a928a790bbd9642d013177046ee73829` in [CI #44123072967](https://github.com/Anrixa/LightsBackON/actions/runs/44123072967). Final documentation revision and merged-main CI remain unverified until those distinct jobs complete.

## Corrective implementation
- Replace eight provisional C06 content/solution JSON files with GRID30, GEN8, healthy west13, east12 broken, 4 PU pump with a 120-tick access latch, and exclusive COLD_STORE 5 PU TEMP/GRID paths.
- Host-only cumulative unsupplied timer, strict 1200-tick cutoff, safe supply rooted in approved GRID or GEN without overload, durable fail-closed restore and authoritative HUD readout.
- Replace provisional timer test suite with 12 boundary/host/negative/legacy checks and complete C06 host-intent replay. Preserve historical provisional receipts without rewriting their outcomes.
- No save deletions, no migration, no Steam changes.

## Observed exact-head CI
- PR #169, branch head `5c4ede08a928a790bbd9642d013177046ee73829`: [run #44123072967](https://github.com/Anrixa/LightsBackON/actions/runs/44123072967), **Linux SUCCESS, Windows SUCCESS**.
- **662 tests passed / 0 failed / 49,080 assertions on EACH OS**.
- **C01–C08 all SOLVED**, C06 in **322 ticks / 41 steps**; Python/Godot parity MATCH on 32 cases, 246 command hashes and 10 definition-rejection checks.
- Windows QA57 Godot UID tracking, SHA512-verified export templates, EXE/PCK release export, headless smoke and manifest source-pin verification **SUCCESS**.
- Earlier source at `a7bddef` had 659/661 tests pass and 2 fail (incorrect type comparison and one phantom outage tick). Corrective commits fixed the actual mid-tick accounting defect and numeric test assertions. These failed runs remain auditable and must not be reclassified.
- Adding this documentation changes the source head: **its own final exact-head CI must pass before merge**; no future result is presumed.

## Required next gates
1. Run exact final documentation PR-head Linux+Windows CI; do not merge on the earlier code-only head alone.
2. Mark PR ready, merge with expected SHA only after required checks succeed; independently verify merged-main CI.
4. Physical Canal Yard, real keyboard/controller/human and target GPU, old deployed C06 checkpoint compatibility, Steam F02/F06 and production acceptance remain **HOLD**.

## Resume notes
PR #169 contains source implementation and observed, named code-head CI. Promotion to physical/release certification remains HOLD; merge-main evidence will require a separate verified receipt.
