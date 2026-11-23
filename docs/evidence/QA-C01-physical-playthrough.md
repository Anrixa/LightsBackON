# Evidence: QA-C01 physical C01 playthrough through the player's input path

- Status claimed: tooling + one fix; closes V02's "known-solution playthrough with real positions and reach" pending item
  (V02 stays CLOUD_VERIFIED, parked on F02 and on people)
- Date (UTC): 2026-11-23
- Branch: `task/QA-C01-physical-playthrough` from `main` `a1cffca`
- Environment: owner's Windows 11 PC, RTX 5090 Laptop GPU (driver 621.24), Godot 4.7.2 editor console binary; windowed 1280x720 and
  `--headless`. Isolated user dir (temporary `override.cfg`, not committed); the owner's saves were not touched.

## What it is
`scripts/diagnostics/c01_playthrough_driver.gd`, started by `boot.gd` with `-- --c01-playthrough` (internal exports and editor only).
- Navigation: a navmesh baked at runtime from the street's **static colliders** (`max_climb 0.05 m`: the controller has no step-up,
  so only real ramps count). No authored waypoints.
- Movement and aim: `move_forward` and the look axes (`Input.action_press`), closed loop on yaw and pitch, until the scene's own
  target selector (the reticle prompt) picks the entity.
- Tools: from `action_for`, the same plan the on-screen prompt shows ("Required tool: Screwdriver" -> slot 2). When the prompt says
  "Read the JE junction meter before working on the exposed trunk", it walks back up and re-measures, as a player must.
- Every command goes through `session.interact` and the host checks (range, physics sight, lock owner, tool, state).
- Writes `user://c01_playthrough/result.json`; exit 0 only on mission complete.

## Observed result
```
godot --headless --path . -- --c01-playthrough
C01_PLAYTHROUGH_RESULT ok exit=0 elapsed_s=137.0 presses=35 remeasure_trips=2 walked_m=321.5 stars=3
```
Windowed run: same route, `RESULT ok` at 139.4 s.

## Findings
| Severity | Finding | Action |
|---|---|---|
| P3 (fixed) | Results screen kept the field HUD ("Gather at the van to finish"), the onboarding card ("First repair completed") and the last toast visible behind the debrief. | `_finish` hides HUD, onboarding and status toast; asserted in `test_QA62_results_grab_controller_focus_and_block_world_input`. Screenshot `QA-C01/after_results_clean.png`. |
| Design (owner) | The east trunk repair forces **two** round trips from the basement to the street-level JE cabinet to re-measure (after isolate, and again before test), about 30 s of walking each run. Rule is deliberate (prove-dead evidence, ADR-005/006), so not changed. | Raise at the A05 slice study: consider a meter port in the basement or one re-measure. |
| Not a defect | The bot first stalled stepping onto the **side** of the basement stair ramp (0.2 m ledge). Players use the stair foot; the stair itself is climbable both ways. | Navmesh climb set to 0.05 m. |

## CI
`.github/workflows/ci.yml` linux job: new step runs the playthrough headless after `run_tests.sh` and requires `RESULT ok exit=0`.

## Not verified
Feel, pacing and discoverability for people (UX01), controller hardware, co-op/Steam, GPU frame time.

## Resume notes
Merged with this PR. Next: the dispatch station label declutter (separate branch).
