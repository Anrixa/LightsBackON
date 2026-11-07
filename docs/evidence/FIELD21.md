# FIELD21 — deterministic live crew HUD work summary

## Demonstrable defect

The S06 `HudPresenter.crew_rows()` iterated the host snapshot's repair
Dictionary in insertion order. The host repair service permits a participant
to own multiple repair locks. Which active repair appeared in that person's
single HUD chip therefore depended on order of snapshot construction, not on
a stable game rule. Similarly, a defensive carried-item lookup took the first
matching dictionary entry; its result could change when the same snapshot
entries were reordered.

## Implemented

- Sort the stable authored repair IDs once and choose the first repair lock
  belonging to each player. The chip remains one concise localized task.
- Sort equipment IDs before choosing the carried-kind summary.
- Preserve local-first crew ordering, repair-over-carried-item priority,
  localization, host ownership, all commands and the authoritative state.
- Six dedicated pure-GDScript regressions in
  `tests/unit/test_FIELD21_deterministic_crew.gd`: reversed-lock order,
  stable crew order, repair/equipment priority, carried equipment, idle
  players and reordered equipment dictionaries.
- No new art, SDK, network channel, save migration or Steam dependency.

## Verification / outstanding gates

Require exact-head Linux and Windows full `bash tools/run_tests.sh`,
Windows release export and exported-build headless smoke, CodeQL and
applicable resource checks prior to merge. Recheck merged `main` CI.

This cloud/headless correction is not a GPU/controller playtest or proof of
legible S06 at 720p, and it cannot promote V07, V09, A04, F02/F06 or the
human visual acceptance gates. Physical Windows performance and UX remain
open.

## Resume notes

Only merge when CI is green for the final source head. Revisit UI task
priority only if a later authored gameplay requirement defines an explicit
priority; do not infer selection order from transient dictionary insertion.
