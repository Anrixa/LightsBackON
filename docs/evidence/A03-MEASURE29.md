# MEASURE29 — local C01 producer terminal integrity

- Base: MEASURE28 merge `f2c6199e0bdb3cc8ac35ac85b30d4b9204c801c0`.
- Scope: C01 opt-in GDScript recorder; no networking, saves, authority, public telemetry or report-schema change.
- Status: implementation on task branch. Exact-head Linux and Windows test CI, Windows export/headless smoke and CodeQL remain required before merge.

## Defect and repair

The offline Python validator tightened terminal-event provenance in MEASURE25, but the originating Godot recorder's generic `note` path could still emit repeated completion, two first-repair observations, results before completion, events after results, or additional events after a departure.

The recorder now enforces terminal-state invariants **at the time an event is appended**. It retains the legitimate ordering of `session_completed`, same-tick objective updates, then `results_opened`. The `first_repair` uniqueness guard applies whether the dedicated helper or generic event path is used. State resets on `begin` and precompleted-checkpoint exclusion, and cannot be changed by a rejected or dropped event.

A clean completed export without an observed `session_completed` is refused rather than creating a file that cannot pass the MEASURE21 validator. A completed run cannot be exported as a departure. Event-budget overflow remains recorded as dropped data for conservative analysis, not falsely repaired.

## Automated verification

Six new Godot integration regressions, plus updates to MEASURE14 and MEASURE19 expectations, check terminal cardinality, results ordering, permitted same-tick objectives, departure finality, missing completed-event refusal and conflicting outcome refusal.

Verify via `bash tools/run_tests.sh` on both CI platforms, including the existing MEASURE01–23 integration suite, and Python unit discovery; Windows exported EXE/PCK headless smoke and CodeQL must pass at the exact PR head.

## Unverified

This is headless code-path verification only. Physical Windows controller/graphics, external V09/A05 player observations, informed participant consent and F02/F06 Steam multiplayer networking are not proven. No original milestone should be marked DONE from these tests alone.
