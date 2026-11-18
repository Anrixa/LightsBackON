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

## Failed first exact-head CI retained (historical)
- PR CI Linux run https://github.com/Anrixa/LightsBackON/actions/runs/44390422748, initial head 8997feaf0d0e6b2631a495759d5eda871202985d: **FAILED**, 770 Godot tests passed and two EXP01 tests failed. The Python generator/content validator and all C01–C12 solution replays passed.
- Root cause: Godot JSON.parse_string converts numeric literals to float. GDScript inspect rejected all mathematically integral preview point values using an incorrect int-only type gate; therefore the UI failed closed, with an empty list.
- Corrective source gate: accept only finite nonnegative numbers at most 200 that equal their exact integer conversion, and add a fractional-point negative case. **Do not count this corrective commit as accepted until new final-head dual-OS CI runs pass.**
