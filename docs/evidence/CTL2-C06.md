# CT-L2 / C06 — Cold-Chain Window: verified headless logic candidate

- Date: 17 November 2026 (GitHub Actions timestamps UTC).
- Branch: `task/CTL2-C06-cold-chain-deadline`; parent `main` `42f1ee718dd8f4ed0561723a67505342547b4769`.
- Implementation source head tested: [`5c704a8fac80041f7c1e320e3511454d8777bdbe`](https://github.com/Anrixa/LightsBackON/commit/5c704a8fac80041f7c1e320e3511454d8777bdbe).
- PR: [#162](https://github.com/Anrixa/LightsBackON/pull/162).
- Observed [Linux/Windows CI #43993660385](https://github.com/Anrixa/LightsBackON/actions/runs/43993660385): both jobs **success**.
- **Status: CLOUD_VERIFIED for original provisional simulation/contract content only**, not a certified original blueprint C06 design or physical gameplay.

## Implemented

Eight contract JSON files under `content/contracts/c06_cold_chain/` (grid/mission/repairs/equipment/meter/switches/tablet/solution), standalone English localization, 10 Godot integration tests, contract spec and CT-L2 tracker.

Gameplay: four required GRID consumers 14 PU total, optional cold store 5 PU, 280-tick grace deadline for the **first host-observed GRID supply** of the cold store. A skipped or late optional service never blocks 100-tick final verification or 50-tick extraction, and earns 2 rather than 3 stars. Separate 80/100-tick pump latches unlock two meter-first repairs; a 6 PU temporary generator can run one 4 PU pump at a time; concurrent operation trips after 15 grid ticks and can be recovered. Full load on GRID is 19/24 PU when optional service is on.

## Observed evidence from exact source tested

- **Linux:** `612 passed, 0 failed, 44096 assertions` and `ALL CHECKS PASSED`.
- **Windows:** `612 passed, 0 failed, 44096 assertions` and `ALL CHECKS PASSED`. Release EXE/PCK export and headless smoke; `QA57_TRACKED_GODOT_UIDS=PASS` and `QA57_EXPORT_PREFLIGHT=PASS`.
- All **69 JSON files** parsed and integer-validated; zero content errors.
- Host solution replays passed on both OS jobs: C01 316 ticks/56 steps, C02 188/44, C03 172/27, C04 206/65, C05 382/62, **C06 382/62**. Simulation ticks are not human performance times.
- Independently re-derived Python parity: **MATCH** on 32 case runs, 246 command hashes, 10 malformed definition rejections and identical content hash.
- The C06-specific tests cover full on-time 3-star completion, exact tick 280 on-time boundary, tick 281 late 2-star outcome, entirely omitted optional, 15-tick overload and safe reset, pump-room access latch boundaries, valid vs forged optional first-supply durable record, invalid deadlines, original C01–C05 checkpoint state shapes.

## Outstanding required gates

1. **Blueprint provenance:** original C06 sheet cannot be verified through current repository file retrieval and was not supplied as text. This project's title, 280-tick grace window and PU choices are provisional authored choices; reconcile against the original 46-page PDF, section for C06 contract, before canonical content qualification.
2. **Physical level:** no C06 scene, Canal Yard geometry, UI cold-chain timer presentation, physical host range checks, human/controller playthrough, GPU P95/memory or screenshots.
3. **Persistence:** addition of C06 rules changes ADR-018 global rules revision. Old incompatible checkpoints remain preserved but may be refused. No migration or deletion performed; source-level earlier-contract state shape tests do not prove cross-version loadability.
4. **External gates:** official backlog CT04 is NOT_STARTED behind CT01 and CT03, and F02/F06 real Steam networks, V09/D08, release qualification remain unfulfilled.
5. This evidence status commit requires **final exact-head Linux and Windows CI**. Do not merge on the preceding implementation-only run.

## Resume

Run CI again on the new evidence/tracker PR head; merge #162 only after both OS jobs succeed on that exact SHA and PR reports clean. Record merge SHA in PR discussion. Continue with CT-L2 C07 only as another separate development phase, without promoting canonical CT04.
