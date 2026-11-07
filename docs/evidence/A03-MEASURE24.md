# MEASURE24 — local consent, retention and measurement quality review

- **Scope:** a read-only, offline C01 review tool to support preparation for A03/A05. This is **not** completion of the original A03 or A05 roadmap gate.
- **Date:** 2026-11-08 UTC.
- **Base commit:** `421395014361f885b177cf1aafdbf45b3927eda5`.
- **Branch:** `task/MEASURE24-local-consent-retention-quality-gates`.
- **Runtime:** Python standard library. No third-party assets, plugins, Steam API, telemetry destination, or save-schema change.
- **Evidence boundary:** headless CI can verify source, outputs and exported Windows headless launch. Physical GPU/controller tests, external player participation and legal/privacy approval are still absent.

## Operator command

```sh
python tools/measure_review.py path/to/local_measurements/
python tools/measure_review.py path/to/local_measurements/c01-report.json
```

A local tool scans at most 100 explicitly selected C01 reports (max 1 MB each)
through the existing strict MEASURE21 JSON/consent/schema validator.
The source folder must not be a symlink, nor may any selected file.
No input content or source path is printed in successful output or in error text.

## What is actually implemented

**Consent boundary:** `opted_in: true` proves only that an observer enabled
the recorder with `--lbo-local-measure`. It does **not** demonstrate an external
participant read a notice, had capacity/consented, or accepted the retention
terms. Every review therefore returns
`HUMAN_PARTICIPANT_CONSENT_REVIEW_REQUIRED` and does not authorize publication.

**Retention triage:** a fixed **30-day operational review window** is evaluated
against each selected file's filesystem modification time. An old file or a
timestamp more than 24 hours into the future blocks aggregate output until
review; selected files are never automatically modified, removed, moved or
uploaded. File mtime is mutable and is **not proof of collection date**.
The 30-day threshold is a conservative review trigger, not a claim about
applicable law or a binding retention rule.

**Quality screening:** counts missing terminal/result/first-repair observations,
nonfinalized idle spans, dropped-event sessions, and canonically identical report
payloads. Missing first repair can be normal for resumed runs; the tool flags
it for review instead of inventing an event. Identical payloads may also occur
naturally, but their reuse is reviewed before a cohort summary is issued.

**Privacy:** only bounded nonidentifying counts, known flag names and the
MEASURE21 aggregate can appear in JSON. No participant ID, session UUID,
event trace, file path, precise mtime or digest is written into the output.
The bounded, already-parsed JSON is canonicalized and fingerprinted only in memory; no second raw file read occurs.

**Failure modes:** invalid consent, unknown keys, malformed JSON, symlink
inputs, oversized files, empty/big selections or unsafe data halt analysis.
Expired/anomalously timed/duplicate reports produce a review result with
`aggregate: null` rather than a misleading set of study metrics.
Quality concerns leave a structurally valid aggregate available but with
`quality.gate: REVIEW_REQUIRED`; all outputs still carry a human-review gate.

## Automated verification

Fifteen MEASURE24 regression cases in
`tests/python/test_measure_review.py` cover:

- Valid reports retaining explicit human-consent/release holds.
- Read-only behavior and omission of paths and identities.
- Expired data and future clock anomalies without deletion.
- Duplicate payloads, including different JSON formatting, preventing unreviewed aggregation.
- Distinct completed and abandoned sessions.
- Dropped events and terminal gaps.
- Missing first repair/results and incomplete idle spans.
- Opt-out or identifying input rejection.
- Symlink refusal (where filesystem permission permits).
- Empty or over-limit input selection.
- CLI error redaction and successful output semantics.
- Inclusive 30-day review-window boundary.

Commands used by the repository's existing CI:

```sh
python -m unittest discover -s tests/python -p 'test_*.py' -v
bash tools/run_tests.sh
```

**Merge gate:** exact-head Linux and Windows CI, Windows export/headless smoke,
CodeQL and any triggered resource probes must be evaluated before merging.
Post-merge `main` CI must be checked. Run identifiers and outcomes go on the PR.

## Operational limitations and resume notes

The tool does not show, collect, or record a human consent form. There is no
safe inference of identity or consent from C01 reports. The operator must
obtain and separately document suitable participant consent before using
external playtester data, and set a jurisdiction-appropriate retention policy
before deployment. Raw reports are local and must not be uploaded or committed.

Next work should concentrate on gameplay/UX or actual V09 ten-run evidence,
not treating aggregate quality flags as proof of playability.
F02/F06 still require two real licensed machines and networks; V09 and A03/A05
milestone acceptance remains pending.

## Security finding resolution

The first CI run at `e33fb342ad30d52d90ac1e26747f6485d5d6d662`
passed Linux and Windows headless export checks but CodeQL reported a
high-severity **clear-text storage of sensitive information** finding at
`tests/python/test_measure_review.py` line 38. The generic fixture writer
was being fed simulated `steam_id`, `peer_id`, and `account_key` test
values in negative cases. The fixture tests now exercise identifier-key
rejection in memory only; the CLI redaction test writes a non-sensitive,
unknown-key marker instead. This preserves the negative assertions without
writing fake personal data to disk. Security approval is pending new exact-head
CodeQL and both-OS CI. No alert was dismissed.
