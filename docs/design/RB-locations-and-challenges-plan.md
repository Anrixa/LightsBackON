# RB: designed locations and solver-checked challenges (rebuild plan)

Decision: `docs/adr/ADR-019-designed-locations-and-challenges.md` (owner, 23 Nov 2026).

Targets:
- 3 districts × 8 locations = **24 designed locations**.
- **12 story contracts** (C01-C12).
- **960 challenges**: 40 per location, in 5 tiers of 8.
- **No developer text on any player screen.**

Rules for every phase:
- One phase per fresh session, on its own branch `task/RB<NN>-<slug>`, ending in a PR merged after the `linux` and `windows` CI jobs pass.
- Each phase writes an evidence file `docs/evidence/RB<NN>.md`.
- The CLAUDE.md stop-and-ask list applies throughout. Third-party assets need the owner first; everything is project-made by default.

## Districts and locations (working names; each location's design sheet refines its identity)

### Alder Street: older brick neighbourhood (contracts C01-C04)
1. **Alder Street:** C01, which exists.
2. Market arcade.
3. Corner pub and terraces.
4. Primary school.
5. Laundrette row.
6. Clinic.
7. Bus depot.
8. Church hall.

### Canal Yard: waterside industry (contracts C05-C08)
1. Pump house.
2. Cold store.
3. Lock gates.
4. Boatyard.
5. Brewery.
6. Warehouse lofts.
7. Rail sidings.
8. Swing bridge.

### Hill Road: hillside homes and services (contracts C09-C12)
1. Water tower.
2. Care home.
3. Radio mast.
4. Terraced cottages.
5. Allotments and greenhouses.
6. Fire station.
7. Quarry office.
8. Lookout café.

**Which contract goes where.** Each contract's spec (`docs/design/CT-*`) names the place it happens. The district design phase
pins each contract to the location in its district that fits that place best.

## Phases

| ID | Phase | Env | Done when |
|---|---|---|---|
| RB01 | **Player text cleanup.** Text table under `content/`; screen-text release check; real names for C01 and the menus; dispatch atlas hidden from the release menu (internal builds only) | local | The check scans every shipped scene and finds no internal ID, `EXP`/`DS` label, raw snake_case or "certification"/"headless" wording; the full suite passes |
| RB02 | **Location format.** Location data schema (kit layout, grid topology, sockets, landmarks, spawn, extraction, look); Alder Street rebuilt from data with the same gameplay node paths; the stage audit runs on it | local | C01 replays byte for byte; C01 bot passes; Alder screenshots match DS08; **owner review** |
| RB03 | **Challenge format and solver.** Challenge schema; Python reference solver; GDScript validator parity; difficulty score; duplicate hash; pillar checks | cloud | The solver solves C01 and the CT contracts; Python/GDScript traces agree byte for byte; pillar checks reject a marker-only and a no-tradeoff case |
| RB04 | **Alder Street challenges and challenge mode.** Generator plus curation for location 1 (40 challenges); location select and challenge board UI (tiers, par, stars, personal records through reward receipts) | split | 40 challenges ship for location 1, every one solved and replayed; the board meets ADR-004 (icon + text, AA contrast 224/224) |
| RB05 | **Second location, end to end** (Market arcade): design sheet, layout, look, 40 challenges. This location is the template for the rest | local | Stage audit passes; three-state screenshot set; **owner review** before batch production |
| RB06-RB13 | **Remaining 22 locations**, about 3 per session: design sheet, layout, landmark, look, 40 challenges each, and the contracts pinned there | local | Per location: audit, screenshots, 40 validated challenges, frame time checked on a QA140 GPU |
| RB14 | **Retire the dispatch levels.** Move still-relevant tests to the new system; remove EXP code; decide saved dispatch progress with the owner | split | Owner decision on saves recorded; suite passes; no EXP text left anywhere |
| RB15 | **Content gate.** 24 locations, 972 missions, difficulty curve report, export frame time on the target class | local + human | Gate report written; **stop for the owner** |

### Order and dependencies
- RB01 → RB02 → RB04 → RB05 → RB06-RB13 → RB14 → RB15.
- RB03 can run at the same time as RB01 and RB02. It is logic only.

## Difficulty tiers (measured, not labelled)

| Tier | Name (working) | What changes |
|---|---|---|
| 1 | Apprentice | 1-2 faults, generous capacity slack, no timed events |
| 2 | Lineworker | 2-3 faults, one required tradeoff, one storm event |
| 3 | Fault finder | Evidence-heavy faults (a misleading label, an intermittent fault), tighter slack |
| 4 | Storm crew | Timed storm events, flood or access tasks, a par time |
| 5 | Master | Several tradeoffs in sequence, little slack, failures that recover but cost time |

The solver measures each challenge's score from its solution:
- solution steps;
- required tradeoffs;
- failing routes;
- meter readings needed;
- time pressure.

A challenge's tier comes from that score. Crew scaling for 1 to 4 players changes the access and logistics load, never the
puzzle's answer, so solo stays fully supported.

## Quality gates for every location

- **Stage audit** (`scripts/diagnostics/stage_audit.gd`): nothing floats, no station sits inside a building, every target is
  reachable, and the spawn is clear.
- **Opening shot:** the spawn frames the location's landmark and the first job. No wall fills the frame.
- **Screenshots:** a three-state set (dark, temporary, restored) at 1920×1080. The location must not read as a copy of
  another one.
- **Player text:** the release check passes.
- **Challenges:** 40, each solved, replayed and pillar-checked, and the tiers spread across all 5.
- **Frame time:** a P95 frame time on at least one QA140 GPU. Unmeasured numbers are labelled targets.
