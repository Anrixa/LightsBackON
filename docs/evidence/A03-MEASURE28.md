# MEASURE28 — V09 local ten-run preflight

- Base: MEASURE27 merge `942cc5bbf077487ef79376dc911b099a08903ab0`.
- Status: implementation complete on branch; exact-head CI, CodeQL, Windows export/headless smoke pending.
- Scope: new offline, read-only Python standard-library CLI. No gameplay, Steam, save schema or analytics collection changes.

## Usage

```sh
python tools/measure_v09_preflight.py path/to/local_C01_reports
```

The tool reuses the bounded MEASURE21/24/26 validator and MEASURE27 quality/aggregate holds. It reports only: count of validated local inputs, ten-run target, structurally aggregatable runs, claimed completions, and fixed evidence status codes. No identifiers, event rows, original filenames, precise timestamps or hashes are exported.

## Interpretation

At least ten structurally valid and aggregatable **reports** may be a candidate for review; ten reports do **not** prove ten human-played, distinct, independent or complete V09 runs. Even ten claimed completions are not an observed no-blocker result. The C01 report schema has no participant-count field, no physical build attestation and no observer record. Four-player tests, real-machine launch evidence, blockers/recoveries and human consent must therefore remain `REQUIRED` or `NOT_OBSERVABLE_IN_REPORT_SCHEMA`.

MEASURE27's `aggregate_gate` prevents stale, duplicated or incomplete measurements from being counted toward the preflight candidate. A passing structural preflight cannot set V09, A03 or A05 to DONE.

## Validation and evidence boundary

Eight tests cover 1/9/10 reports, dropped-event hold, retention hold, invalid opt-in, anonymity/read-only guarantees and CLI error redaction. Required at exact PR head: `python -m unittest discover -s tests/python -p 'test_*.py' -v`, `bash tools/run_tests.sh`, Windows release export/headless smoke, and CodeQL.

Not verified: actual V09 gameplay runs, four-player host/client testing, two qualified Steam PCs/networks (F02/F06), independent recruitment or human consent, physical graphics and controller checks, A05 observations and release.
