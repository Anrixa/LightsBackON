# MEASURE25 — terminal provenance integrity for local C01 measurements

- Scope: offline audit only, extending the existing schema-v1 report validator.
- Base: main at 421395014361f885b177cf1aafdbf45b3927eda5.
- Branch: `task/MEASURE25-terminal-provenance-integrity`.
- Environment: GitHub CI (Linux and Windows headless), pending exact-head execution.
- Original A03/V09 gates remain NOT_STARTED; this is an engineering validation phase.

## Defect prevented

The MEASURE21 validator checked that a claimed run had at least one correct
terminal event, but allowed multiple completion events, repeated first repair
records, results before completion and trailing events after a debrief.
Those patterns can distort cohort counts. MEASURE25 rejects them before
returning any aggregate statistics. Truncated logs with nonzero dropped
events still lack proof of a terminal event and must never have one fabricated.

Godot's real C01 completion sequence emits `session_completed`, then may
observe final objective rows at the same host tick, then opens results.
That legitimate ordering remains valid. An already saved incomplete run
may complete without a fresh first-repair event; it remains eligible.

## Verification

- 11 regressions in `tests/python/test_measure25_terminal.py`.
- Run `python -m unittest discover -s tests/python -p 'test_*.py' -v`.
- Run `bash tools/run_tests.sh` on Linux and Windows CI.
- Windows headless release export and smoke must pass for this exact PR head.
- No report upload, old report migration, save-schema change, Steam integration
  or external participant data; only a stricter local audit.

## Pending and resume notes

Hold merge if Linux/Windows CI, CodeQL or Windows export fails.
Physical GPU/controller, ten real V09 runs, human consent/retention review,
F02/F06 two-network tests and owner milestone gate are not verified.
Continue with MEASURE26 only after this PR is integrated, so toolchain
changes are not silently stacked on an unmerged branch.
