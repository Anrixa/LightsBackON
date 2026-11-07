# MEASURE26 — read-once bounded local report snapshots

- Status: implementation on `task/MEASURE26-single-read-bounded-audit`; exact-head CI required.
- Dependencies: MEASURE24 and MEASURE25 merged into `main`.
- Environment: Python stdlib; Linux and Windows GitHub CI are headless.
- No gameplay, schema, save, networking, telemetry upload, Steam or publishing changes.

## Security and correctness hardening

The prior MEASURE24 review correctly stopped re-opening reports for duplicate
hashes, but the MEASURE21 reader still performed a path-based size check
followed by a separate open, and recorded path-based mtime. A file swapped
between check and open could therefore mismatch the file actually validated.

The reader now accepts **one bounded regular-file descriptor**, compares its
device and inode with the initial non-symlink lstat, adds O_NOFOLLOW where
available, checks size both before and after open, reads at most 1,000,001
bytes, and rejects in-place size or mtime changes during reading. The
canonical JSON fingerprint and retention mtime now correspond to the
validated bytes and opened file descriptor. External `read_report` and
`analyze_input` call signatures and published aggregates remain compatible.

## Validation

Eight regressions: ordinary audit, metadata redaction, exact byte limit,
oversized input, directory/symlink rejection, file swap between stat/open,
growth between stat/open and bad UTF-8. Run full Python unit discovery,
`bash tools/run_tests.sh`, Windows release export/headless smoke and CodeQL
at the **exact PR head** before merge.

## Boundaries and resume

No guarantee is made against malicious privileged OS/filesystem mutation;
the tool remains an offline read-only analysis aid. No real human playtests,
external consent/retention legal approval, physical GPU/controller sessions,
F02/F06 or original A03/V09 gates are claimed.

After merge, review cohort eligibility logic without changing human-study
approval gates or exporting any raw measurements.
