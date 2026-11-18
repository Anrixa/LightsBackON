# EXP01 — Dispatch atlas implementation evidence

## Scope and provenance
- Baseline main: 85f3f6c89fa613bac726b8328d6ec20fe6081d46 (CT-L1/C04 P07).
- Branch: task/EXP01-200-level-dispatch-atlas.
- User-requested world expansion: 25 distinct regions, 200 sites and level briefs, 1,000 proposed objectives and 200 lore objects.
- Changes do not alter the existing 12 host contracts, gameplay power rules, saves, network, reward receipts or Steam.

## Implemented
- scenes/expeditions/atlas.json and docs/design/EXP01-atlas-seeds.json
- Deterministic Python content generator, integrity validator and negative tests
- Read-only Godot atlas reader, searchable/list-based menu overlay and regression tests
- Dedicated main-menu entry, with explicit non-playable design status, no save writes or credits

## Observed acceptance
- Source baseline P07 merged-main Linux/Windows workflow #44384823907 succeeded at SHA 85f3f6c8.
- EXP01 PR-head Godot/Python full suite: **PENDING** until its workflow runs.
- EXP01 Windows QA57 export and merged-main independent CI: **PENDING**.
- Human/controller continuous traversal, physical 200-scene level access, GPU P95/VRAM, Steam and release: **OWNER HOLD**.

## Important limitation
The 1,000 tasks are individually identified design briefs and are **not 1,000 wired host intents**. The 200 level entries are not constructed physical playable scenes; lore items cannot yet be collected; preview points cannot become currency. Acceptance of these features requires following engineering phases and verified source/hardware evidence.

## Resume notes
Review the exact final commit and both Linux/Windows checks. Fix proven errors without weakening tests, merge normally after CI passes, verify independent merged-main checks, then begin EXP02 authored physical layout work.
