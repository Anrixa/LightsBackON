# MEASURE27 — explicit local cohort evidence gate

- Base: MEASURE26 merge `8493924cd2bd48dfccf0565e1c154df91f2f9abf`.
- Scope: read-only C01 offline measurement reviewer; no collection, upload, game state, release, Steam or save changes.
- Status: implementation submitted; exact-head Linux/Windows headless CI, Windows export smoke and CodeQL required before merging.

## Problem and correction

MEASURE24 deliberately retains diagnostic aggregates for sessions with missing observations, dropped events or quality flags. An operator could misinterpret the presence of `aggregate` as meaning the cohort was suitable for a study. MEASURE27 adds `cohort_evidence` independently from `aggregate`, preserving existing consumers and the ability to diagnose imperfect reports.

- `INPUT_INTEGRITY_HOLD`: retention/clock review or normalized duplicate report payload.
- `DATA_QUALITY_HOLD`: missing, incomplete or dropped observations flagged by the established MEASURE24 checks.
- `STRUCTURAL_REVIEW_ONLY`: only automated structural checks are satisfied. This is **not** human consent, playable quality, formal study approval or release acceptance.
- `reasons` lists only fixed non-identifying reason codes.
- `human_study_approval` remains `REQUIRED`, `aggregate_is_diagnostic_only` remains true, and existing `study_gate`/`release_gate` remain unchanged.

## Verification

Seven dedicated Python regressions cover a structurally valid report, old report, duplicate payload, dropped observations with retained diagnostic summary, absent results, absent first-repair, and output privacy/read-only requirements.

Required commands in exact-head GitHub CI:

```sh
python -m unittest discover -s tests/python -p 'test_*.py' -v
bash tools/run_tests.sh
```

Required extra gates: Windows release export/headless smoke and CodeQL. The PR is not ready for merge until these are green. Physical player testing, V09 ten-run study, F02/F06 Steam qualification and approval of real participant consent remain outstanding.

## Handoff

Review any cohort analysis that consumes `aggregate`: it must consider `cohort_evidence.gate` and never represent `STRUCTURAL_REVIEW_ONLY` as participant approval. Continue with measurement analysis only after the PR is merged and main's checks remain healthy.
