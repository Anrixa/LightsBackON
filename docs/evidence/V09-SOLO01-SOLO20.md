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

## Observed CI and acceptance boundaries

- Verified implementation head: `20cc5810540033b63752b8542ca5aeb9f89f5a5d`.
- [Linux + Windows full CI, run #42271966192](https://github.com/Anrixa/LightsBackON/actions/runs/42271966192): **PASS on both hosted operating systems**, 378 Godot tests, 0 failures, 9,228 assertions on each.
- C01 reference solution: **SOLVED**, 316 ticks / 56 steps on both runners; re-derived Python reference cross-check **MATCH**, 32 case runs, 246 command hashes, 10 invalid-definition rejections.
- Windows runner: **PASS** source-preserving UID check, Godot 4.7.2 export, exported EXE headless smoke, manifest pin validation, hash generation and artifact upload. This is not a physical GPU launch.
- [QA51 isolated lifetime probes, run #42271966122](https://github.com/Anrixa/LightsBackON/actions/runs/42271966122): **PASS** on Linux/Windows; all observed CanvasItem, ObjectDB, DummyTexture, ShapedText and FontRID deltas were zero.
- Initial [run #42271611748](https://github.com/Anrixa/LightsBackON/actions/runs/42271611748) had 378 Linux/Windows tests passing but failed the Windows QA57 UID sidecar gate. Both missing tracked UID files were added; the subsequent exact-source-head run above passed. English multiline text was also corrected before the passing run.
- This documentation update changes **no** GDScript or content. Final documentation-commit exact-head CI and subsequent post-merge main CI must still be recorded before claiming integration.
- Physical GPU, real controller-only playthrough, real two-network Steam, UX01 and V09 acceptance: **NOT RUN**. V09 remains NOT_STARTED; F02 remains BLOCKED.

## Resume notes

Do not merge before final PR-head Linux/Windows, export/smoke and QA51 gates pass. No promotion of V09 or original blueprint task statuses is permitted based on this batch. Continue with real GPU first-person acceptance, offline C01 playtesting and the blocked Steam F02 qualification separately.
