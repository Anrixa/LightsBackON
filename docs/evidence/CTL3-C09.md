# CT-L3/C09 — Wind Warning original-sheet implementation

- Original design: Development Blueprint v1.0 pp.18,20. Branch `task/CTL3-C09-wind-warning-host` from verified CT-BP-GATE merged main `2e5dd7adae05cdab6663dcea560290a70a441999`.
- Current status: **IN_PROGRESS**, no successful CI assumed prior to an actual run.
- Authoritative new content: `content/contracts/c09_wind_warning/` (8 JSON definitions including a complete host solution).
- Hill network: GRID28, 14 PU west/east feeders; GEN6; west hall6+bakery4+greenhouse3 = 13, east flats5+telecom4+garage3 = 12. Initial failed/tripped JW west fuse and unhealthy JE east trunk.
- Wind schedule: warning at 600 host ticks; roof entry closed from 900 through 1300 **inclusive**, reopens at tick1301; safe return offered to host-recorded rooftop occupants at closure. Ground route always accessible, not blocked by wind. No weather-driven random grid damage or forced falls.
- Host `use_route` enforces session/peer membership, deduplication, rate, empty payload, authored route ID and real server-side range. The first approved route grants east repair access. Source-only contract logic does **not** claim physical player relocation or in-scene route traversal; physical navigation target (~20 extra seconds by ground) requires a Hill scene and timed user study, not an invented 200-tick wait.
- Optional work light: 2 PU GEN-powered, 100 uninterrupted ticks to latch; no penalty to core mission on omission.
- New C09-only durable `wind_routes` receipt holds mission elapsed and access route; validates shape/types and refuses forged grant/timer before mutation. Rooftop occupancy remains ephemeral and must be reconciled by safe physical spawn on a real scene.
- Existing C01–C08 durable shapes are unchanged. No migration or save delete performed.

## Tests, traces and pending gates

`tests/integration/test_CTL3_C09_wind_warning.gd`: 11 tests covering source numbers, warning ticks, roof/gust boundaries, ground-only alternative, host invalid intents, solution replay, optional omission, stable grid under gust, fail-closed checkpoints, malformed definitions and earlier contract compatibility. C09 solution trace has 54 authored steps.

**MANDATORY before promotion:** exact final-head Linux and Windows CI, C01–C09 replays and Python/Godot reference parity; independent merged-main CI and Windows QA57 export. Preserve failed CI receipts accurately. Source-only ceiling: `SOURCE_ALIGNED_HEADLESS_CANDIDATE`.

**HOLD:** Hill physical level/sockets/route geometry, safe-return physical transition, warning HUD/accessible presentation, controller/human playthrough, target GPU frame-time/memory, old shipped save compatibility, real two-network Steam F02/F06, canonical CT06 and production.

## Resume notes

If CI is red, inspect the job log, correct actual source/test defects, then re-run exact final head. After merged-main verification, begin separate **CT-L3/C10 — Community Night** PR with original-sheet specification in `docs/design/CTL3-C10-C12-blueprint-spec.md`. C11 and C12 follow independently.


## Observed code-head CI — 17 November 2026 (UTC)

Implementation source `e0f7336b368463f817a1265fe0ffec4c30ec46ae`, [GitHub Actions #44136706464](https://github.com/Anrixa/LightsBackON/actions/runs/44136706464):

| Check | Linux | Windows |
| --- | --- | --- |
| Godot tests | **673 passed, 0 failed, 50,107 assertions** | **673 passed, 0 failed, 50,107 assertions** |
| Content validator | 93 JSON files, 0 errors | 93 JSON files, 0 errors |
| C01–C09 host replay | all SOLVED | all SOLVED |
| C09 solution | **197 ticks, 54 steps** | **197 ticks, 54 steps** |
| Python/Godot reference | MATCH 32 cases, 246 hashes, 10 rejects | MATCH same |
| Windows release export and QA57 | N/A | **PASS** EXE/PCK, headless exported smoke, script UID and source pin |

All 11 C09 tests passed on both platforms. This verifies **source/headless** contract behavior, not an actual roof or ground route scene, target GPU, checkpoint restore from a prior released version, or human navigation.

**Important:** This evidence/tracker addendum changes the PR head. The final documentation SHA must itself pass Linux/Windows CI before merge. Afterwards verify merged-main dual-OS CI separately. Never treat a pending run as a pass.
