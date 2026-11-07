# MEASURE29 — C01 external-study funnel and denominator integrity

- Source PR branch: `task/MEASURE28-external-study-denominators` (historical name prior to phase-number collision); source-implemented, exact-head CI pending.
- Dependencies: MEASURE24–27 merged; original A05 remains **NOT_STARTED**.
- Runtime: Python stdlib only, read-only local input, no network or telemetry.
- No game, save, Steam or human-study data is modified.

## Why this phase exists

Original backlog A05 calls for **six outside pairs** plus **three solo
sessions** and an explicit denominator/recruitment-bias assessment. Counts
must distinguish *approached, eligible, consented, started, completed* and
*included* sessions, or an observer could overstate success by reporting
only successful completions.

`tools/measure_study_denominators.py` accepts an **identity-free,
self-reported aggregate JSON**, never names, IDs, dates, channels or raw
playtest events. Strict allowlists block unknown fields; nonnegative bounded
integer counts must be monotonic by stage. Each pair is **one session** but
two participant seats. The locked A05 planning targets are six pair sessions,
three solo sessions (15 total participant seats).

The output provides exact count denominators, stage attrition, included
shortfalls and zero-denominator `null` rates; it never creates a measured
human study from a plan. Even a self-reported full funnel retains explicit
`OPERATOR_DECLARATION_ONLY`, consent/recruitment bias HUMAN review and
`REAL_SESSION_EVIDENCE_NOT_VERIFIED` gates. Sampling bias, real consent,
legitimate two-human participation and usability outcomes cannot be
established by aggregate counts alone.

## Usage

Start with the all-zero template
`docs/study/MEASURE29-DECLARED-COUNTS-TEMPLATE.json`. For a genuine
future human study, prepare a separate aggregate-only local JSON after
obtaining consent and appropriate review. No raw participant logs should
be committed.

```sh
python tools/measure_study_denominators.py docs/study/MEASURE29-DECLARED-COUNTS-TEMPLATE.json
python -m unittest discover -s tests/python -p 'test_*.py' -v
bash tools/run_tests.sh
```

File reads reject symlink/directory, cap inputs at 32 KiB, validate the
opened inode and recheck post-read file size and modification time. Errors
return only stable codes rather than local paths or input strings.

## Verification and pending gates

13 new MEASURE29 Python regression tests cover empty and full declarations,
stage attrition, pair-versus-person arithmetic, invalid stage ordering,
identifying/unknown fields, out-of-range values, schema drift, read-only
file behavior, symlinks, oversized/malformed JSON, duplicate keys,
nonfinite numbers and CLI output redaction. Exact-head Linux and Windows
CI, Windows release export/headless smoke and CodeQL required before merge.

Still missing: actual outside participant recruitment, informed consent,
sample representativeness/recruitment bias review, observed timings,
replay choices and failure causes, ten V09 playthroughs, real four-player
and F02/F06 two-network Steam tests. Nothing here closes A05 or V09.

## Resume notes

MEASURE29 can provide strictly aggregate-only comparison of declared study
denominators against eligible independently reviewed C01 local reports,
but **must not infer human participation or attempt to link identities**.
