# CT-BP-GATE — original-blueprint source closeout (C02–C06)

- Observed: 18 November 2026 (UTC+8).
- Baseline: `6400b71691c69f6b8f571916554957ad48d7b43b` on canonical `Anrixa/LightsBackON`.
- Authority: original Development Blueprint v1.0 pp.18–20, C02–C06 individual corrective specifications, and the GitHub receipts listed below.
- Decision: **SOURCE_ALIGNED_HEADLESS_CANDIDATE** for C02–C06; **HOLD** for physical/full-original-blueprint certification, real saves and release.

## Primary verified final-head and merged-main CI receipts

| Contract | Final PR source | Final PR dual-OS CI | Merged main | Merged-main dual-OS CI |
| --- | --- | --- | --- | --- |
| C02 [#165](https://github.com/Anrixa/LightsBackON/pull/165) | `aab09babb174` | [#44003856923](https://github.com/Anrixa/LightsBackON/actions/runs/44003856923) SUCCESS | `300703ef494d` | [#44004321714](https://github.com/Anrixa/LightsBackON/actions/runs/44004321714) SUCCESS |
| C03 [#166](https://github.com/Anrixa/LightsBackON/pull/166) | `e8d630239f14` | [#44035197037](https://github.com/Anrixa/LightsBackON/actions/runs/44035197037) SUCCESS | `7b1f39d4e5be` | [#44035670547](https://github.com/Anrixa/LightsBackON/actions/runs/44035670547) SUCCESS |
| C04 [#167](https://github.com/Anrixa/LightsBackON/pull/167) | `76083f56af4a` | [#44041957106](https://github.com/Anrixa/LightsBackON/actions/runs/44041957106) SUCCESS | `4d7fcd355a45` | [#44042394225](https://github.com/Anrixa/LightsBackON/actions/runs/44042394225) SUCCESS |
| C05 [#168](https://github.com/Anrixa/LightsBackON/pull/168) | `06e24f9bf991` | [#44047118657](https://github.com/Anrixa/LightsBackON/actions/runs/44047118657) SUCCESS | `5544eaed2c16` | [#44047679775](https://github.com/Anrixa/LightsBackON/actions/runs/44047679775) SUCCESS |
| C06 [#169](https://github.com/Anrixa/LightsBackON/pull/169) | `f077ff307d23` | [#44124117210](https://github.com/Anrixa/LightsBackON/actions/runs/44124117210) SUCCESS | `6400b71691c6` | [#44124773627](https://github.com/Anrixa/LightsBackON/actions/runs/44124773627) SUCCESS |

Every listed final-source PR-head and push-on-main `ci` workflow was explicitly checked on GitHub as **SUCCESS**. Linux and Windows jobs were present and green for C06 final PR head and merged main; every recorded `ci` run for the other corrected merges also concluded SUCCESS.

The C06 final source run is not to be confused with its previous code-only receipt: [#44123072967](https://github.com/Anrixa/LightsBackON/actions/runs/44123072967) separately reported 662 passed/0 failed/49,080 assertions **per OS** and all C01–C08 solutions solved. This does not substitute for later exact-head CI, which is recorded above.

## Gate engineering added in this phase

- `docs/design/CT-BP-SOURCE-GATE.json`: machine-readable immutable record of the five final PR and merged-main receipts.
- `tools/check_ct_blueprint_gate.py`: offline fail-closed checker for original blueprint-sensitive PU topology, 50/100/120/1200/1800 tick definitions, correct venue/bonus mode, duplicate IDs, CI-receipt consistency and preserved physical HOLD state.
- `tests/python/test_ct_blueprint_gate.py`: positive baseline and negative cases for generator capacity, cumulative outage, venue pairing, improper promotion, mismatched CI receipt, duplicate feeder ID and missing mission file.
- Existing GDScript authoritative host regressions, solution replays and cross-language reference remain the dynamic behavior tests. The Python gate is **structural**, not a replacement for runtime proof.
- `CT-L1`, `CT-L2` and corrective trackers reconcile stale PR/merge placeholders. Historical provisional CI and discrepancy findings are not overwritten.

## Unqualified acceptance

Actual C02–C06 scene construction, playable socket placement, in-world interaction and controller/human sessions, exported real Windows target-GPU P95/memory, actual historic release checkpoint compatibility, and two-real-network Steam F02/F06 **remain HOLD**. Canonical `docs/backlog.json` D08 and CT03/CT04/CT05 are not promoted by this track. No user save/data or Steam resources are changed.

## Next roadmap phase

**CT-L3/C09** is the next separate design-first source development task, followed by C10–C12. Before C09 content is authored, transcribe the exact Hill Road C09 sheet from blueprint pp.20–21 into an explicit original-source spec and test matrix. Build full grid, mission, repairs/equipment, host intents, canonical replay and negative tests. Do not infer gameplay constants or create unofficial level names. CT-L3 source-only work is allowed under ADR-017; canonical CT06 depends on CT02/CT05 and cannot be set DONE ahead of those gates.

## Resume notes

This PR itself requires final exact-head Linux/Windows CI, Python negative tests, C01–C08 solution replay, reference parity and Windows export/headless QA57. Mark source-only CT-BP-GATE PASS only after that PR HEAD succeeds and a separate merged-main CI receipt exists. Physical and release gates remain HOLD independently.
