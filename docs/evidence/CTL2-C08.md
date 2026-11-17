# CT-L2/C08 — Split Supply (original blueprint implementation candidate)

- Date: 17 November 2026.
- Authority: original repository `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf`, pp.18, 20–21, read from the page content streams.
- Main baseline: `5cd24e75e8cdaf805d3ce4bb10cbf3e1d327c8d3` (merged C07).
- Work branch: `task/CTL2-C08-split-supply-blueprint`.
- Status: **IN_PROGRESS — NOT YET CLOUD_VERIFIED / NOT ORIGINAL-BLUEPRINT CERTIFIED** until final exact-head Linux and Windows CI, full content replay, export smoke and QA57 complete.

## Authored host semantics

A (18 PU) supplies Canal west (LAUNDRETTE5, DINER4, ROW_HOUSES4; 13/14 feeder). B (16 PU) starts offline, east DEPOT4, COLD_STORE5, PUMP_KIOSK3 (12/14 feeder) disconnected. Independent A-to-JE tie has 14 PU and starts open.

On the approved solution, shed laundrette and row houses (9 PU), keep diner4, connect A tie to supply east12 (A source16/18), sustain depot power for 100 consecutive 10 Hz ticks, and unlock B cabinet. Inspect and repair B under isolated JE using the supplied B relay. **Open A tie before closing B-to-JE feeder.** Only then restore west loads, leaving A13/18 and B12/16.

A new optional `grid_sources` mission field supports multiple authorized permanent sources while retaining legacy `grid_source`. A source over its own PU limit is not accepted as valid C08 depot access or final verification supply. The existing authoritative graph validator refuses any attempt to close B feeder while A tie energizes JE, atomically and without a one-tick phantom dual feed.

The optional `DINER_UNINTERRUPTED` bonus is monitored after **each processed host command** as well as every 10 Hz host tick: even a power-off and recovery between ticks permanently loses the bonus but never prevents six-load completion. Its conditional one-boolean durable receipt is validated before restore; C01–C07 checkpoint shapes remain unchanged.

No new real-physics electrical claims, client-side power authority, speculative physical Canal Yard positions, portable source or scene-certified interaction targets were added.

## Tests authored (execution pending)

`tests/integration/test_CTL2_C08_split_supply.gd` checks baseline/source/feeder/demand, exact 3-star known solution, timed access latch, interrupted timer reset, source-overload abuse, atomic dual-supply refusal, one-tick break-before-make transition, same-tick DINER interruption bonus loss, durable save validation and tampering rejection, bad source and optional definitions, two-player host replay and legacy C01–C07 save shapes.

Required verification before any merge or CLOUD_VERIFIED label: full Linux and Windows suite on the **final** PR head; solution validator C01–C08; content validator, Python reference parity, Windows export/headless smoke, QA57, and QA51 resource probes where applicable. Record actual job counts, exact commit and run URLs after observing them.

## Certification limits and corrective track

C02–C06 retain `HOLD_CONFIRMED_MISMATCH`; the recorded defects in `docs/evidence/CTL2-BLUEPRINT-RECONCILIATION.md` are independently tracked for corrective implementation (not waived by C08's success). C07 and C08 source-aligned headless implementations still require physical level/controller/UX validation. Official CT05 remains NOT_STARTED behind CT04; F02/F06 Steam two-network tests and V09/D08 human acceptance remain unqualified. No existing saves have been migrated or deleted.

## Resume notes

Finish exact-head Linux/Windows CI, repair any regressions, update this evidence with observed results, and merge only after both required hosted operating systems pass. Then begin dedicated C02→C06 original-blueprint corrections on separate branches, each with new solution replay and falsification tests; never promote provisional content solely because its old CI passed.
