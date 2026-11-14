# MEASURE33 — deterministic JSON nesting rejection (CI portability)

- Status: source implementation in review; exact-head CI remains required.
- Date: 2026-11-14.
- Base: `main` `4cd98a81c53907ef8e4916e1d349a2f0be1acbf6`.
- Trigger: DS10 PR #146 CI Linux job reported **524 Godot tests, zero failures**, but an existing MEASURE21 Python regression failed: deeply nested list returned `INVALID_ROOT_KEYS` on that runner rather than `INVALID_JSON` expected by the test. Windows DS10 job passed. No DS10 code or game schema was implicated.

## Implementation

- `tools/measure_report.py`: scan the already bounded single file snapshot to reject raw JSON object/array nesting beyond 64 before calling `json.loads`. Ignore delimiters in quoted strings and handle escaped quote/backslash correctly. This removes interpreter/decoder-dependent deep JSON acceptance while retaining the existing validation and privacy rules.
- `tests/python/test_measure_report.py`: cover ignored quoted brackets, accepted depth 64, rejected depth 65. The preexisting 10,000-nested-array MEASURE21 test remains unchanged and must now pass consistently.
- No game, checkpoint, authority, telemetry, data deletion or UI changes.

## Required verification

1. Exact-head Linux and Windows `bash tools/run_tests.sh`, including all Python reference tests, 500+ Godot tests, content checks and C01 solution.
2. Windows export and headless build smoke, relevant Github Actions CI.
3. Recheck DS10 PR against the merged baseline; do not treat the prior failing run as passed.

## Not verified

No local or CI execution result is asserted here yet. This patch intentionally fixes the input parser's safety boundary and a preexisting test, not a gameplay bug.

## Resume notes

If the CI suite fails, inspect the failing test and correct only a proven cause; only merge after Linux and Windows gates pass.
