# CT-L1 / C02 — Dinner Rush: authored Alder contract

Date: 17 November 2026. Governed by ADR-017 decision 3 and the DS07 parallel content track. **This is logic/data qualification only**, not backlog CT03 promotion or a claimed playable C02 mission.

## Distinct C02 player experience

The Lantern has an opening-time requirement. The east feeder and west junction are independently damaged. The recommended route is to inspect and repair the **east trunk** promptly, energize the Lantern sign, then resolve the west fuse, verify all five service buildings, and extract. The sign is an **optional venue load**, not an essential light or a hidden repair instruction.

- Source GRID = 24 PU; west trunk 12 PU (4 apartments + 5 market = 9 PU); east trunk **15 PU** (4 pub + 4 east apartments + 3 workshop + optional 3 sign = 14 PU). Two separate faults: `JW.failed` and `E_GRID_JE.healthy=false`. The generator remains available, but the known solution does not require moving it or pumping a basement.
- Optional opening deadline = **2,400 host ticks = four minutes** at the established 10 Hz grid rate. This is a **design choice**, not measured difficulty or official platform fact. A sign first supplied from GRID within the window earns the optional service credit **only if still on-grid at completion**. Reaching the window late still permits full mission completion, but yields one fewer star.
- The existing 100-tick final verification and 50-tick extraction apply without any extra player, equipment, optional grind or hard fail at venue opening. No time star or fabricated real-world electricity.
- Meter-first repair, one lock owner, isolation/tool state machine, host-source attribution, 1.5 s trip protection and C01 player safety rules are reused. A generator-to-pub route while the grid already energizes PUB must be refused with no topology mutation.

## Engineering contract and boundaries

Eight complete C02 JSON definitions in `content/contracts/c02_dinner_rush/` and new English keys; source/switch/consumer IDs deliberately reuse the Alder authored district to avoid ungrounded level coordinates. `mission_director.gd` supports an optional `optional_deadline_ticks` **only when specified**, recording the first qualifying GRID tick and persisting this counter with strict restore validation; missing field preserves C01's original canonical/durable state shapes.

`solution.json` replays full host intents through the existing SessionHost pipeline, with no simulated bypass of failed validation. `tests/integration/test_CTL1_C02_dinner_rush.gd` validates the known solution, missed-deadline completion and lesser reward, refusal of dual-supply topology without mutation, invalid deadlines, durable first-supply integrity and C01's unchanged checkpoint payload shape.

## Content revision and preservation

New contract rules under `content/` can change the global **rules revision** even when the older C01 files themselves are unchanged. Under ADR-018, a previously saved checkpoint with another rules revision is preserved and rejected with an explicit mismatch, not deleted or silently migrated. No save migration, destructive cleanup, or public rollout is authorized here; before user-facing packaging, qualify a contract-scoped revision policy separately if cross-version C01 continuation is required.

## Remaining gates

No selectable C02 mission scene, full authored encounter geometry, physical keyboard/controller first-repair run, timing playtest or second-network Steam qualification has been claimed. C02 is an **authored content candidate**; do not set `docs/backlog.json` CT03 to DONE or CLOUD_VERIFIED. CT03's D08 dependency remains unchanged. CT-L1 next parts C03 Roof Route and C04 The Whole Block have no implementation evidence yet.
