# CT-L2/C07 — Wrong Label: verified cloud logic evidence

- Date: 17 November 2026.
- Authoritative original design: `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf`, p.18 Canal baseline, p.20 C07 Wrong Label (extracted and read from the connected repository PDF).
- Base main: `bbcd245f376e7ddde3ac7ea5cc0611eae97c693b` (merged C06).
- Implementation branch: `task/CTL2-C07-wrong-label-module-evidence`.
- Source head verified: [`f9f7b5ffa89e08ef5e5df4535318097f4a3084db`](https://github.com/Anrixa/LightsBackON/commit/f9f7b5ffa89e08ef5e5df4535318097f4a3084db).
- PR: [#163](https://github.com/Anrixa/LightsBackON/pull/163).
- Full cross-platform successful implementation run: [#43996169752](https://github.com/Anrixa/LightsBackON/actions/runs/43996169752).
- Status: **CLOUD_VERIFIED for blueprint-aligned headless power, repair, meter-evidence and mission logic.** Physical district, controller/GPU and save-across-build checks remain HOLD.

## Changes delivered

Original source has Canal GRID30, west/east feeder 14, GEN8. West LAUNDRETTE5/DINER4/ROW_HOUSES4=13 is initially supplied; JE initially tripped, east DEPOT4/COLD_STORE5/PUMP_KIOSK3=12 is dark. The old installed E_GRID_JE module is 10 PU but the physical stale label says 14; `PANEL_JE` meter reports `capacity_pu=10, demand_pu=12` only after a host inspection.

A separate `replace_module` command is implemented inside `PowerGrid` with an exact, authored protected-feeder whitelist. Normal host intents cannot submit arbitrary capacity writes; the authorized eight-stage repair installs the provided `MODULE_14PU` only while JE is isolated. Checkpoint causes retain only an allowed replacement capacity and reject other ratings with rollback.

A C07-specific conditional host mission evidence record awards `EVIDENCE_MISMATCH` only when real JE meter evidence has been inspected before the first in-range JE reset attempt (successful or refused). A wrong 12/10 reset is rejected as `RESET_OVERLOADED` but consumes that bonus opportunity, never the ability to finish the mission. The conditional evidence record is validated/round-tripped with the mission save; earlier C01–C06 save field shapes remain unchanged.

Eight C07 contract JSON definitions, a 25-step host-intent solution, eleven new Godot regression tests, localization, tablet data, source-aligned specification and non-destructive blueprint discrepancy audit were committed. No C01–C06 contract definitions were silently rewritten.

## Observed tests — run #43996169752

- **Linux:** 623 passed, 0 failed, **45,208 assertions**; `ALL CHECKS PASSED`.
- **Windows:** 623 passed, 0 failed, **45,208 assertions**; `ALL CHECKS PASSED`.
- **Content:** 77 JSON files validated, **0 errors**.
- **Known solutions on each OS:** C01 316 ticks/56 steps; C02 188/44; C03 172/27; C04 206/65; C05 382/62; C06 382/62; **C07 169/25**. Simulation ticks are not human playthrough timing.
- **Reference parity:** MATCH on 32 case runs (forward and reversed), 246 command hashes, 10 malformed definition rejections, matching content hashes; reference is independently re-derived, not the originally supplied oracle.
- **Windows QA57:** `QA57_TRACKED_GODOT_UIDS=PASS`, `QA57_EXPORT_PREFLIGHT=PASS`, official release EXE/PCK export and headless smoke.
- New tests cover exact PU/feeder math, actual meter readings vs stale label, full 3-star solution, refused reset and 2-star recovery, repeated reset and 15-tick overload from unshedding the consumer, generic capacity mutation refusals, author-whitelisted isolated upgrade, meter-before-repair requirement, capacity save restoration and forgery rejection, durable evidence receipt validation, invalid module definitions and legacy mission saves.

The first test iteration [#43995924580](https://github.com/Anrixa/LightsBackON/actions/runs/43995924580) observed 621 passing tests and two assertion failures (JSON float-vs-int comparison and invalid authored-upgrade test assumption); corrected on the source head above before the successful run. Neither was a host-simulation defect.

## Unclosed gates

1. C07 has no physically implemented Canal Yard service scene. The correct stale plate and meter display, in-world repair panel, range, real controller/keyboard, human comprehensibility, GPU P95/memory and screenshots remain unverified.
2. No actual Windows save/reload across incompatible global rules revisions, no migration/deletion of saves; snapshot-shape regressions are narrower.
3. Steam F02/F06 separate networks and official backlog CT05 remain gate-blocked. The source-aligned C07 implementation is not production/release certified.
4. The recovered original PDF revealed **confirmed blueprint mismatch** in prior C02–C06 authored contracts, detailed in `docs/evidence/CTL2-BLUEPRINT-RECONCILIATION.md`. They retain historical headless CLOUD_VERIFIED labels, with fidelity HOLD.
5. This evidence/tracker update itself requires a **final exact-head Linux and Windows CI**. Merge only after both pass on its precise SHA.

## Next phase

Once final-head verified, merge PR #163 and log merge SHA in PR discussion. Next independent authoring phase by roadmap: CT-L2/C08 Split Supply (source A18, B16, exclusive 14 PU ties and zero-dual-supply transition); source-fidelity corrective C02–C06 work is mandatory before canonical content promotion.
