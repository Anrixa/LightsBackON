# MEASURE33 — deterministic JSON nesting rejection (CI portability)

- Status: code and test correction verified in Linux and Windows CI on head `e159c42fe6b67545441582941d8418f405ecfc1d`; this evidence-only update requires its own final-head rerun before merge.
- Date: 2026-11-14.
- Base: `main` `4cd98a81c53907ef8e4916e1d349a2f0be1acbf6`.
- Trigger: DS10 PR #146 CI Linux job reported **524 Godot tests, zero failures**, but an existing MEASURE21 Python regression failed: deeply nested list returned `INVALID_ROOT_KEYS` on that runner rather than `INVALID_JSON` expected by the test. Windows DS10 job passed. No DS10 code or game schema was implicated.

## Implementation

- `tools/measure_report.py`: scan the already bounded single file snapshot to reject raw JSON object/array nesting beyond 64 before calling `json.loads`. Ignore delimiters in quoted strings and handle escaped quote/backslash correctly. This removes interpreter/decoder-dependent deep JSON acceptance while retaining the existing validation and privacy rules.
- `tests/python/test_measure_report.py`: cover ignored quoted brackets, accepted depth 64, rejected depth 65. The preexisting 10,000-nested-array MEASURE21 test remains unchanged and must now pass consistently.
- No game, checkpoint, authority, telemetry, data deletion or UI changes.

## Executed verification

- PR #147 CI run [#43544053542](https://github.com/Anrixa/LightsBackON/actions/runs/43544053542), at source head `e159c42`: **Linux SUCCESS, Windows SUCCESS**.
- Both hosts: former failing `test_MEASURE21_refuses_forged_idle_durations_and_unbounded_nesting` PASS; new `test_MEASURE33_depth_limit_is_parser_independent_and_string_safe` PASS.
- Both hosts: `bash tools/run_tests.sh` PASS, **518 Godot tests / 0 failed / 42,372 assertions**, C01 SOLVED in 316 ticks, cross-check MATCH (32 scenarios; 246 command hashes).
- Hosted Windows: QA57 tracked Godot UID PASS, Windows release build export and headless smoke PASS, QA57 exported EXE/PCK/manifest preflight PASS.
- This record-only update creates a new exact PR head; rerun `ci` at the final head before merging.
- Recheck DS10 PR against the merged baseline; its earlier Linux run was red and cannot be counted as passed.

## Not verified

CI was run on GitHub-hosted Linux and Windows; no separate physical PC or human testing was performed. The patch intentionally fixes the input parser's safety boundary and a preexisting test, not a gameplay bug.

## Resume notes

If the CI suite fails, inspect the failing test and correct only a proven cause; only merge after Linux and Windows gates pass.
