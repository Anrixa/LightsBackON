# MEASURE23 — exclude precompleted checkpoints from new playtest completions

- **Status:** implementation staged for exact-commit CI; not a completed V09/A03 roadmap gate.
- **Date:** 2026-11-07 UTC.
- **Base `main`:** `58f91ccc131cefeeef3976b0f602f4b4c296a01a`.
- **Branch:** `task/MEASURE23-precompleted-checkpoint-exclusion`.
- **Environment:** GitHub Linux/Windows headless CI; physical GPU/controller and real human playtests not performed.
- **Dependencies:** the existing MEASURE01–MEASURE22 recorder, mission UI and G06 local checkpoint codec. No new assets, external dependencies, Steam, telemetry, save changes, or publication operations.

## Defect and fix

A previously completed C01 checkpoint can be reopened with **Continue Shift**. The mission correctly restores its frozen results and displays the results screen. Previously, the opt-in measurements recorder was initialized as if the player had started a new shift, then the results screen finalized and wrote a second `outcome=completed` report. Repeated viewings could therefore inflate playtest completion counts, even though no new mission was solved.

The live C01 scene now checks the **authoritative restored mission completion state**, only after a successfully restored checkpoint supplies a valid saved view, before displaying that checkpoint's results. For a precompleted session, the recorder:

1. Drops the transient `session_started` and any in-memory observations.
2. Disables itself permanently for that recorder instance.
3. Refuses subsequent `begin(true)` and `finish_and_export` calls with a stable `PRECOMPLETED_CHECKPOINT` reason.
4. Creates **no** new local measurement JSON report, even if the player opens or exits the results screen.
5. Does **not** affect results rendering, controller focus, saves, or legitimate playthrough statistics.

Fresh shifts and incompletely restored shifts keep normal opt-in capture. A newly created recorder for a later shift is eligible normally. Legacy reports already exported before MEASURE23 are not modified or deleted.

## Regression coverage

Seven MEASURE23 tests are appended to `tests/integration/test_MEASURE20_local_events.gd`:

- Exclusion removes the transient session-start and earlier in-memory data.
- Excluded recorders cannot rearm or export; repeating exclusion is idempotent.
- New opt-in runs still produce truthful completed reports.
- Exclusion is scoped to one recorder and never poisons a subsequent shift.
- An unfinished resumed mission remains measurable.
- A host-completed restored mission shows its debrief and controller exit focus but cannot create a new report.
- Ordinary eligible completion still records repair, success and results events.

The scene regression reconstructs a completed authoritative mission state in the headless sandbox without touching personal save files. The existing G06 suite separately covers real checkpoint serialization and restore. These tests do not replace physical playtests.

## Verification commands and CI gates

```sh
bash tools/run_tests.sh
python -m unittest discover -s tests/python -p 'test_*.py' -v
```

Exact PR-head `linux`, `windows`, Windows release export/headless smoke, resource isolate and static analysis checks must pass before merge. Verify fresh `main` CI after merge.

**Not verified:** physical Windows gameplay and controller feel; a complete real solo/group run; F02/F06 two-account Steam; V09; study recruitment, consent and retention; A03 human acceptance; publishing.

## Resume notes

After merge, continue with one verified unblocked phase. Prefer validation tooling for consent, retention, and selection-bias study notes, or real physical C01 playtest capture when appropriate. Never label the original V09 or A03 tasks DONE without their own evidence.
