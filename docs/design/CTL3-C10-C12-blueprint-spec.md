# CT-L3/C10–C12 — original Hill Road source specifications and engineering queue

Source: original Development Blueprint v1.0 pages 18, 20–21 (27 October 2026). These are **verified design constraints**, not implemented/CI-qualified missions.

Shared baseline: `GRID28`, feeder `14/14`, `GEN6`; west required hall6 + bakery4 + greenhouse3 = 13 PU; east required flats5 + telecom hut4 + service garage3 = 12 PU. Final required load 25 PU.

## CT-L3/C10 — Community Night

Hill baseline GRID28, feeders14, GEN6; east healthy, west fuse failed.

- Hall6 belongs to west13.
- Event stage3 through west would be west16/14, so refuse unsafe route.
- Separate GRID-to-STAGE spur rated4 requires isolated host installation.
- After final required25 plus optional3, source GRID28/28 exactly.
- Stage3 needs 100 uninterrupted ticks before event start at second240 / host tick2400.
- Missed optional never blocks core contract.

Acceptance on separate C10 PR: complete contract JSON, host-only command/repair/equipment implementation, authoritative timing state, negative route/overload and optional-loss tests, full solo and two-player solution replays, fail-closed checkpoint boundary, C01–prior regression, final-head Linux+Windows and merged-main CI. Physical/human/GPU/Steam remain HOLD.

## CT-L3/C11 — Borrowed Power

Hill baseline GRID28, feeders14, GEN6; west supplied, east trunk broken.

- Telecom4 temporarily from GEN6 and garage control4 cannot operate at once (8/6).
- Shed greenhouse3 to reduce west13 to10; then west-to-telecom alternate gives14/14.
- Break-before-make exclusive temporary and WEST bypass for telecom.
- Garage control4 requires 100 host ticks before east repair.
- Switch telecom to repaired east GRID, re-enable greenhouse.
- Optional: no telecom interruption greater than50 consecutive ticks; misses never block repair.

Acceptance on separate C11 PR: complete contract JSON, host-only command/repair/equipment implementation, authoritative timing state, negative route/overload and optional-loss tests, full solo and two-player solution replays, fail-closed checkpoint boundary, C01–prior regression, final-head Linux+Windows and merged-main CI. Physical/human/GPU/Steam remain HOLD.

## CT-L3/C12 — Lights Back On

Hill baseline GRID28, feeders14, GEN6; failed west protection and broken east.

- GEN4 drain/control load needs120 uninterrupted ticks to expose east repair.
- Optional finale beacon3 must use direct GRID spur4, not overloaded west route (16/14).
- Required Hill supply25 and beacon3 makes GRID28/28 exactly.
- Beacon needs100 uninterrupted supply ticks.
- On verification, 2-second staggered restored lights and short radio subtitle; player input stays active.
- Results offer replay and remaining optional tasks, not an endless game claim.

Acceptance on separate C12 PR: complete contract JSON, host-only command/repair/equipment implementation, authoritative timing state, negative route/overload and optional-loss tests, full solo and two-player solution replays, fail-closed checkpoint boundary, C01–prior regression, final-head Linux+Windows and merged-main CI. Physical/human/GPU/Steam remain HOLD.

## Sequencing and safety

C09 first and with its own exact-head CI. Then C10, C11, C12 each in an **independent** branch/PR from merged main. No hypothetical PU values, forced migration of old saves, synthetic physical measurements or unofficial CT06 DONE promotion. Official CT06 depends on CT02/CT05. Content and source headless acceptance is only `SOURCE_ALIGNED_HEADLESS_CANDIDATE`.
