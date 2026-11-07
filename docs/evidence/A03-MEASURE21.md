# MEASURE21 — privacy-safe local report audit

- **Status:** implementation committed for CI; NOT the completion of A03 or V09.
- **Date (UTC):** 2026-11-07.
- **Branch:** `task/MEASURE21-privacy-safe-report-audit`, based on `cdddb78d959d9627c40ef100e396b49290ee9591`.
- **Environment:** isolated Python 3 execution; no Godot, GPU, controller, Steam, or Windows test claimed in this evidence.
- **Related original backlog task:** A03, `NOT_STARTED` until V09's physical/people gates pass.

## Scope and acceptance

After the merged MEASURE01–MEASURE20 recorder, MEASURE21 adds a **read-only offline auditor**
for locally recorded, explicitly opted-in C01 sessions. It cannot change game state or upload data.

`python tools/measure_report.py <local-report.json>`

`python tools/measure_report.py <local_measurements_directory>`

The input is validated against the *actual* exported schema version 1: strict allowlisted
root/event keys; explicit opt-in; C01 contract; host-tick ordering; objective ordinals;
bounded idle durations, report size, count, and events; double-key and malformed-input
rejection; terminal outcome consistency; no symlink traversal.

Successful output is a single aggregate JSON document with session/outcome counts,
median host-tick completion/first-repair timings, observed objective elapsed
durations, idle spans, protection trips, hints, event budget losses, and separate
explicit human-review and release-gate markers. It contains **no** raw event rows,
account keys, peer IDs, participant names, file paths, or network destinations.

The analyzer **does not collect consent**: only reports already produced with
`--lbo-local-measure` are eligible. No reports are copied to the repository or
any remote system. Raw report handling, human consent/retention, and anonymized
study recruitment still require their own procedures before A05.

## Tests

Local isolated source verification:

```text
python -m unittest discover -s tests/python -p 'test_*.py' -v
Ran 7 tests in 0.600s
OK
```

The seven MEASURE21 regressions cover summaries, identity refusal, invalid
event order/payloads, duplicate keys/invalid UTF-8, multiple-session aggregation,
CLI redaction on error, and event overflow/finalization.

**GitHub exact-head Linux/Windows CI, Windows release export/smoke, and QA51
resource checks must be inspected before merging.** Do not mark them passed
based on the isolated test above.

## Not verified

No live opt-in C01 session, Windows GPU/controller evaluation, Steam peer
disconnect capture, two-network testing, or human playtester analysis.
No assertion of real-world usability, statistical confidence, V09 completion,
A03 completion, A05 completion, or publication readiness.

## Resume notes

1. Inspect PR exact-head Linux/Windows CI and resource checks; fix failures.
2. With owner-approved local consent, run C01 using `--lbo-local-measure`,
   analyze the **local** exported directory and review whether the observations
   represent the playthrough accurately. Do not upload raw reports by default.
3. Preserve V09 and F02 hardware/Steam limitations; use original A05 human
   gate for outside-player consent and study evidence.
