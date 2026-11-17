# CT-L2/C07 — Wrong Label: verification record

- Date: 17 November 2026.
- Source: original blueprint PDF pp.18,20; read from the repository (previously inaccessible in prior phases).
- Branch: `task/CTL2-C07-wrong-label-module-evidence`, base main `bbcd245f376e7ddde3ac7ea5cc0611eae97c693b`.
- Status: **IN_PROGRESS — CI pending**. The C07 content and specialized host rules are not considered verified until passing full two-platform CI.

## Work

Eight JSON contract definitions, host solution trace (meter → isolated module replacement → verify → extract), localization, new host-only meter-evidence bonus, isolated whitelisted integer capacity replacement, protected capacity save restoration and C07 regressions. Full review is in `docs/design/CT-L2-C07-contract-spec.md`.

## Required cloud acceptance

- [ ] Linux + Windows full Godot suite, exact solution validator C01–C07, JSON validation and Python reference parity.
- [ ] Meter accuracy 10 actual / 12 demanded vs stale physical 14; no evidence bonus without first real inspection.
- [ ] Wrong reset refused without grid mutation; bonus lost after first reset, including refused reset, but mission always recoverable.
- [ ] Generic arbitrary/rushed module replacement and forged saved capacities refused; repaired module persists after save/restore.
- [ ] Three-star correct solution vs two-star wrong-reset solution, 15-tick overload recovery, and old C01–C06 unchanged mission save shapes.
- [ ] Windows release EXE/PCK/headless smoke, QA57 UIDs and QA57 export preflight.
- [ ] Full exact documentation-head rerun, PR merge, authoritative main SHA recorded in PR discussion.

## HOLD: physical and canonical

No Canal Yard authored scene, stale cabinet label render/UX test, physical meter display, real host range, human/controller playthrough, target GPU P95/memory, Steam F02/F06 two-PC networks or cross-version existing-save continuity. `docs/backlog.json` CT05 stays NOT_STARTED behind CT04. Old incompatible checkpoints remain preserved. Blueprint-alignment mismatches in C05/C06 require separate corrective work.
