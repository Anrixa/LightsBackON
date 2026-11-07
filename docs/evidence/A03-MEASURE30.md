# MEASURE30 — observed completion-clock truth and sample-gated P95

- Branch: `task/MEASURE30-observed-completion-timing`.
- Status: implementation staged; exact-head Linux/Windows CI and CodeQL pending.
- Dependencies: MEASURE25 terminal integrity; MEASURE27 review holds; V09 A05 evidence.
- Scope: offline C01 report validator and aggregate timing calculations only.

## Correctness issue addressed

The original `session_duration_median_ticks` reports the final exported
local-observation tick across BOTH completed and abandoned runs. The results
screen can open after the host signaled `session_completed`. Therefore that
single metric cannot honestly represent *time to mission completion* or a
completed-run distribution.

The MEASURE30 validator now records `completion_observed_tick` from the
validated, ordered, authoritative `session_completed` event. It is
`null` for opt-in logs with missing completion terminal (only possible when
events were dropped), and it does not invent one from a declared outcome.
The existing mixed-outcome duration median remains unchanged for
backward compatibility; new output fields are distinct:

- `completed_elapsed_sample_count`: reports with an observed completion.
- `completed_elapsed_median_ticks`: median actual completion event tick.
- `completed_elapsed_p95_ticks`: nearest-rank (noninterpolated) P95 only if
  at least ten observed completions and **all input reports** have intact
  terminal/debrief/idle observations and no dropped events.
- `completed_elapsed_p95_gate`: explicit reason P95 is suppressed.
- `completed_elapsed_timing_basis` and
  `completed_elapsed_human_evidence`: local 10 Hz host ticks (paused
  host time excluded), and NO physical/person acceptance implied.

Ten is the existing V09 structural-run target, **not** a statistical
confidence guarantee. We do not call this wall-clock time, human sampling
proof or evidence of four-player acceptance. Every aggregate still has
`HUMAN_PLAYTEST_REVIEW_REQUIRED` and `NOT_EVALUATED` release gate.

## Regression coverage

12 dedicated regressions in
`tests/python/test_measure30_completion_timing.py` test:

- delayed debrief vs actual completion, abandoned sessions, zero observations;
- nine vs ten completions, nearest-rank P95 at twenty, mixed outcomes;
- dropped events, missing results, unfinished idle, missing resumed repair;
- unchanged raw schema, no raw events or identifiers and missing terminal.

Run `python -m unittest discover -s tests/python -p 'test_*.py' -v` and
`bash tools/run_tests.sh`; require exact PR-head Linux and Windows,
Windows release export/headless smoke, CodeQL and applicable resource checks.
This phase cannot verify physical Godot rendering, hardware/controller play,
human timings, V09/A03/A05 or F02/F06 two-network Steam.

## Resume notes

After green CI and merge, real opt-in, consented C01 sessions are needed to
evaluate actual timing distributions and bias. Do not add further fabricated
sample or completion reports to the repository. MEASURE31 should only start
on a concrete remaining software defect, not as a substitute for human work.
