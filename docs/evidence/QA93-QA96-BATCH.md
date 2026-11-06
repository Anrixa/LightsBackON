# QA93–QA96 — Tablet boundary and input-ownership hardening batch

Baseline: `cbaebe5891ae24ed973a8a6e726c6bd7f6a518ac` (post-QA92).
Each phase is built on the preceding phase's merged `main`, with a separate branch, PR, test and evidence file.

| Phase | Verified implementation scope | PR |
| --- | --- | --- |
| QA93 | Reject malformed tablet snapshots before replacing a live navigable view and losing correlated requests | #97 |
| QA94 | Require literal boolean `ok` on host acknowledgments, preventing malformed response coercion into false success | #98 |
| QA95 | Block reentrant tablet-origin sends from overwriting the original synchronous dispatch sequence | #99 |
| QA96 | Require an opened, visible tablet visit before processing global input or changing controller zoom latch | #100 |

## Gates

Per-PR verification: exact-head Linux and Windows headless tests, Windows export/smoke and QA51 resource probes. Final phase must also pass post-merge main CI. **Do not treat this file as an assertion of future CI success:** inspect exact PR head SHAs and GitHub Actions run conclusions.

## Boundaries

- UI-only changes; no grid authority, power rules, host/transport, save/reward schema, content, or third-party assets.
- Physical Windows GPU/P95/memory, real controller UX, human UX01/V09 studies, two-PC separate-network Steam F02/F06, store publishing and any external approvals remain pending. Issue #51 remains open.
- No original `docs/backlog.json` milestone is promoted by these offline QA phases. The 66-item blueprint remains the authoritative milestone plan; QA93–QA96 are supplemental regression phases.
- No measured work-hours were logged. Do not invent duration, hardware results or Steam certification.

## Resume notes

Check QA96 postmerge main CI and the four merged PRs. Continue a new phase from the exact latest main commit. Do not start blocked Steam/publishing work without owner approval.
