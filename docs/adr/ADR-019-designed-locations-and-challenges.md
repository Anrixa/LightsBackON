# ADR-019: 24 designed locations with about 1,000 solver-checked challenges replace the 200 generated dispatch levels

- Status: **Accepted**, 23 Nov 2026, owner decision in a desktop session.
  - The owner asked for 200 unique locations with 1,000 challenges, and invited a better proposal.
  - Claude proposed this plan instead, and the owner chose it ("Your plan: ~24 locations").
- **Changes a locked decision** (CLAUDE.md section 1, world scope), with the owner's approval.
- **Supersedes the scope in `docs/design/EXP01-expansion-architecture.md`.** That scope was the owner's update of 19 Nov 2026:
  200 locations, 200 levels and about 1,000 tasks, built by a seeded generator.
- **Amends the cut order** (point 6 below).
- Does not change: the power rules (CLAUDE.md section 3), host authority and networking (section 4), save and receipt contracts,
  the demo, or any honesty rule.

## Context

**What the owner saw on 23 Nov 2026.** On the 200 dispatch levels the owner saw developer text on screen ("load_a dark",
"Job_001/1", "EXP011 energize or shed", "NO PLAYABILITY CERTIFICATION"). The owner also found that the levels all look alike:
"It seems that everything is very bad."

**What the inspection found.**
1. **The levels are generated from one recipe.**
   - The EXP layers are about 18,600 lines in 55 files (`scripts/gameplay/expedition_*.gd`, `scripts/world/exp*.gd`,
     `scripts/world/expedition_*.gd`).
   - They were built as a stack of experiments, EXP06 to EXP021, each adding its own signs, boards and controls.
   - The DS look pass (`docs/evidence/DS-dispatch-look.md`) could re-skin them but not make them distinct. From the spawn,
     levels in one region are almost the same frame (`docs/evidence/DS-stage-audit/spawn_sheet_121.jpg`).
2. **Developer text is written directly to the screen.**
   - It is spread through those files: internal IDs, task numbers, phase names and a roughly 100-word controls string of
     developer notes.
   - There is no single text table, so nothing stops an internal ID from reaching the player.
3. **A location is art; a challenge is data.**
   - Alder Street (C01) is the only area that meets the ADR-004 quality bar, and it took many sessions of design work.
   - 200 locations at that standard is not a realistic target.
   - Generating them is what produced 200 look-alike levels.
   - The power puzzle is abstract (integer PU, a canonical state, solution traces that a validator replays). Its challenges can
     therefore be generated, solved, scored and checked automatically.
4. **The core is sound.** The grid, repair, mission, equipment, save, reward and sync logic is headless-tested: the full suite
   passed 1079/0 on 23 Nov 2026. C01 is proven finishable by real input (the QA bot from PR #307).

## Decision

### 1. World scope: 3 districts × 8 locations = 24 designed locations

- The districts are **Alder Street**, **Canal Yard** and **Hill Road**, the blueprint's districts (CT01, CT02).
- Each district has 8 service locations instead of the blueprint's 6.
- Every location is designed individually from the modular 4 m kit, to the Alder Street standard (ADR-004, ADR-016):
  - its own landmark and layout;
  - its own skyline and lighting identity;
  - a design sheet, a screenshot set and a stage audit.
- No location is procedurally assembled. Procedural code may place small dressing inside an authored layout and nothing more.

### 2. Story campaign: C01-C12 stay

- The 12 contracts remain the campaign spine, each pinned to one of the 24 locations.
- Their data, rules and solution traces do not change because of this ADR.

### 3. Challenges: about 1,000, all solver-checked

- **Count.** Each location gets 40 challenges in 5 difficulty tiers of 8 (24 × 40 = **960**). With the 12 story contracts
  that is **972** missions.
- **What a challenge is.** A data record on an authored location. It sets:
  - which faults exist, and where;
  - the capacities and demands;
  - temporary supply;
  - timed storm events;
  - flood and access state;
  - the par time;
  - crew scaling for 1 to 4 players.
- **How challenges are made.**
  1. A generator proposes candidates.
  2. A solver proves each candidate solvable and records its solution trace. The trace is replayed by the same validator as
     the contracts (`tools/godot/validate_solution.gd` and the Python reference, byte for byte).
  3. A difficulty score is measured from the solution: steps, required tradeoffs, failing routes, evidence needed, time
     pressure. Tiers come from the measured score, not from a label.
  4. Near-duplicates are rejected by a canonical-state hash.
  5. A curation pass picks and names the shipped set.
- **Pillars apply to every challenge.**
  - Every challenge needs meter evidence: no challenge can be finished by following markers and holding Interact.
  - Every challenge has a temporary-supply tradeoff.
  - Every challenge ends with visible recovery.
  - A challenge that fails a pillar check is rejected automatically.

### 4. Player text: one table, no internal IDs on screen

- Every word the player sees comes from a text table under `content/` with a real name, for example "Market Street feeder",
  never `load_a`.
- Internal IDs stay internal. Engineering detail is shown only on the F3 diagnostics overlay in internal builds.
- A release check scans every visible Label, Label3D and Control text in every shipped scene, and fails the build on:
  internal ID patterns, `EXP`/`DS` phase labels, raw `snake_case`, or "certification" and "headless" wording.

### 5. The 200 dispatch levels are retired

- **Hidden first.** When the player-text phase lands (RB01), the dispatch atlas leaves the release main menu and stays
  available only in internal builds.
- **Removed later.** The EXP code is removed only after the new challenge mode ships. Tests that cover rules still in use move
  to the new system first.
- **Saves.** Any saved dispatch progress is preserved and never silently erased (CLAUDE.md section 5). How it is handled is
  an owner decision at removal time (stop-and-ask: migrating or deleting save data).

### 6. Cut order (amended)

- **Old:** voiced barks, cosmetic variants, seeded replay variants, contracts 12 to 8, districts 3 to 2.
- **New:** voiced barks, cosmetic variants, **challenges per location 40 to 20**, **locations per district 8 to 6**, contracts
  12 to 8, districts 3 to 2.
- "Seeded replay variants" is replaced, because the challenges are now the core replay content.
- Never cut: the power puzzle, recoverable failures, solo support, working co-op, save integrity, readable feedback. To these
  this ADR adds: **no developer text on player screens**.

## Consequences

- **The rebuild plan.** `docs/design/RB-locations-and-challenges-plan.md` lists the phases (RB01 onward). Each phase runs in a
  fresh session (CLAUDE.md section 6 step 0).
- **Backlog.** The `docs/backlog.json` statuses do not move because of this ADR.
  - CT01/CT02 (district kits), CT03-CT06 (contracts) and CT09 (replay templates) are carried out through the RB phases.
  - Each of those tasks keeps its own acceptance.
- **Owner review.** The owner reviews screenshots after the location template (RB02) and after the second location (RB05),
  before the remaining locations are built in batches.
- **Honesty.**
  - The location count and challenge count are targets until shipped and checked.
  - Difficulty tiers are measured by the solver; whether they *feel* right needs people (the D07/B-milestone studies).
  - Nothing here qualifies co-op or the Steam transport (F02/F06).
