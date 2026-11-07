# MEASURE27 — hold incomplete cohorts rather than publish false denominators

- Scope: MEASURE24 offline read-only reviewer only.
- Status: branch `task/MEASURE27-aggregate-observation-integrity`; exact-head Linux/Windows CI and CodeQL pending.
- Dependencies: MEASURE24–26 merged into main.
- No local report schema change, game-state change, uploaded telemetry or publication.

## Reliability rule

A claimed `outcome=completed` is not itself a complete observed session
when events were dropped or the required terminal/debrief was not captured.
An open idle span makes measured idle time incomplete. Previously the reviewer
marked such cases `quality.gate=REVIEW_REQUIRED` but still returned an
aggregate of completion and duration metrics. That aggregate is now withheld
(`aggregate=null`) with an explicit `aggregate_gate` reason.

Gate precedence: retention anomalies first, duplicate equivalent payloads
second, incomplete observations third, structurally available otherwise.
`quality.sessions_incomplete_observation` counts distinct affected reports,
not a sum of overlapping quality flags. First-repair absence alone is NOT a
hard hold: a resumed shift may have no newly observed repair. It retains a
review flag and null repair median. All cases still require human consent
and human playtest review; no study or release approval is inferred.

## Tests and compatibility

Nine focused MEASURE27 regressions, plus updates to the existing MEASURE24
tests that previously allowed questionable aggregates, cover:
success, dropped events, missing results, open idle, resumed repair absence,
overlapping failures, hold precedence and truthful mixed outcomes.

Verify full Python unit discovery, `bash tools/run_tests.sh`, Windows
export/headless smoke and CodeQL at the exact branch head.

## Unverified / resume

No real participant sessions, physical GPU/controller, V09 ten-run gate,
F02/F06 networking, human consent review or milestone A03/A05 approvals.
MEASURE28 can establish a reproducible sampling protocol without collecting
or publishing player identities.
