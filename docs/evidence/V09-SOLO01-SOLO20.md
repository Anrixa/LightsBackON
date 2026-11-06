# V09 preparation — SOLO01–SOLO20: live C01 shift operations

**Scope:** production read-only operation status for the existing offline C01 scene; a single cohesive batch of twenty implementation/test substeps, **not** twenty original roadmap tasks. V09 remains NOT_STARTED because the Steam/two-network gate and ten real solo/group runs are outstanding. F02 remains BLOCKED.

**Design invariant:** no mutation of power evaluation, command authority, mission conditions, checkpoint schema, rewards, networking, or original 66-task backlog. Do not show uninspected fault causes.

| Substep | User-visible or system behavior |
| --- | --- |
| SOLO01 | Count all six actual C01 objectives. |
| SOLO02 | Name the first actionable objective. |
| SOLO03 | Keep hidden/pending objectives out of the current-task instruction. |
| SOLO04 | Update completed objective count after authoritative transitions. |
| SOLO05 | Use the mission-defined pump interval, not a copied UI timer. |
| SOLO06 | Show continuous pump-drain progress while temporarily supplied. |
| SOLO07 | Preserve the drained presentation after its durable latch. |
| SOLO08 | Display mission-defined final grid verification progress. |
| SOLO09 | Reset progress when supply stops meeting grid verification. |
| SOLO10 | Move to equipment-stow stage after verification. |
| SOLO11 | Prevent premature departure-readiness messaging. |
| SOLO12 | Distinguish stowed equipment from actual crew-at-van readiness. |
| SOLO13 | Present ready-to-depart only when all prerequisites hold. |
| SOLO14 | Show a countdown derived from the host mission state. |
| SOLO15 | Clear countdown presentation on cancellation. |
| SOLO16 | Display immutable completed-run state, not a fresh departure prompt. |
| SOLO17 | Surface host-recorded protection trips (never fabricate a success badge). |
| SOLO18 | Surface host-recorded recovery count. |
| SOLO19 | Keep the projection read-only and separate from durable save state. |
| SOLO20 | Integrate the localized, controller-scrollable pause briefing and richer final debrief in the actual C01 scene. |

## Implemented

- New pure `scripts/gameplay/shift_operations.gd` presents host-authored milestones and bounded percentages.
- `OfflineC01Session.shift_operations_view()` exposes only approved mission/equipment/zone status.
- Existing pause panel receives an accessible live briefing, pump/verification/departure progress bars and readiness/trip/recovery information. Results gain original host-recorded trips, preventable trips, recoveries, completion tick, and equipment return.
- English string keys drive all new labels; no third-party assets, unqualified Steam transport, user identifiers or telemetry upload are introduced.
- Twenty Godot tests check the new presentation contract, including real offline session and scene construction.

## Verification

- Linux full suite: PENDING exact PR-head CI.
- Windows full suite: PENDING exact PR-head CI.
- Windows release export and headless smoke: PENDING exact PR-head CI.
- QA51 resource probes: PENDING.
- Post-merge main CI: PENDING.
- Physical GPU, controller-only playthrough, real two-network Steam, UX01 and V09 acceptance: NOT RUN.

## Resume notes

Do not merge before final PR-head Linux/Windows, export/smoke and QA51 gates pass. No promotion of V09 or original blueprint task statuses is permitted based on this batch. Continue with real GPU first-person acceptance, offline C01 playtesting and the blocked Steam F02 qualification separately.
