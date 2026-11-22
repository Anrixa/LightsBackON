# EXP015 A12.15 — Verified-behavior repair follow-up

The first cache repair preserved authentic negative-response replay while refusing cached successes on obsolete regional hosts. This follow-up closes another retained-object side-effect path: `SessionHost.receive()` previously called `_mission.observe_supply_state()` even after a retired owner rejected a new command. The live source may have advanced in a successor dispatch, but the old session may not rewrite evidence, mission progress or a host-visible revision.

The production SessionHost now observes live supply only for an active regional owner (legacy non-regional sessions remain unaffected). An existing 25-region regression now asserts the retired host mission's canonical state remains identical across rejected stale commands and duplicate denials. The owner current host continues to accept authorized operations.

New exact unreviewed host blob: `69a1ac7ca3602b2f318298ee335d4143c78bd592`. The earlier repair blob is retained as an historical reference; the A12.16 descendant source gate must require this latest blob. No owner holds are changed.
