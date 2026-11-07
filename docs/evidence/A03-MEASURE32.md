# MEASURE32 — fail-closed direct C01 measurement timing summaries

## Scope and observed defect

The read-only `tools/measure_review.py` used MEASURE27's observation-integrity
hold. However, `tools/measure_report.py` is also a public offline command and
its direct `analyze_input()` path still printed timing medians computed from
incomplete observations, even when events were dropped or a completed session
had no results-open observation. Its MEASURE31 P95 had a hold, but the other
medians were still presented as usable measurements.

## Changes

- Apply the same observation-completeness precondition in direct `summarize()`
  before publishing **any** timing median or sum.
- Require zero dropped events, one matching observed terminal, a results-opened
  event for completed runs and paired idle boundaries for each report.
- An observed first-repair event is **not** mandatory: a resumed run can
  legitimately have no new repair.
- Hold mixed cohorts as a whole; retain raw/declared session counts and
  diagnostic event counters only, explicitly separated from observation
  eligibility. Suppressed timing fields return `null`.
- Add `observation_gate`, `sessions_with_incomplete_observations`, observed
  terminal counters and explicit nonclaims about retention/duplicates and
  participant consent. Do not imply that a passing structural gate establishes
  a validated study.
- Nine Python regression tests in
  `tests/python/test_measure32_direct_summary.py`.
- No change to report schema v1, producer GDScript, gameplay, offline saves,
  Steam, network authority, file retention, deletion or uploads.

## Verification requirements

The exact PR source head must pass `python -m unittest discover -s tests/python -p
'test_*.py' -v`, full Linux and Windows `bash tools/run_tests.sh`,
Windows release export/headless smoke, CodeQL and any triggered resource probes
before merge. Verify post-merge `main` as a separate gate.

The local authoring environment has no pinned Godot binary and does not
qualify a headless Godot or Windows GPU test. Do not claim any human
participant, controller, visual, ten-run V09, A03/A05 study, F02/F06 Steam or
release acceptance from this change.

## Resume notes

Finish exact-head CI review and only merge on green. MEASURE31's completion
clock and 10-observation tail floor remain unchanged. MEASURE32 is corrective
work, not a request to extend the analytics roadmap indefinitely; after this,
prioritize real game acceptance and outstanding roadmap gates.
