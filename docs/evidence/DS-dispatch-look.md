# Evidence: DS dispatch-stage look (Alder Street Stormglass look on the 200 dispatch levels)

- Status claimed: presentation fix with tests; no backlog status change. Owner feedback on 23 Nov 2026: the dispatch units
  "look absolutely terrible", and "only Alder Street looks good".
- Date (UTC): 2026-11-23
- Branch: task/EXP-dispatch-label-declutter (the same PR as the label declutter; both touch the same stage file, so they
  are not stacked as separate branches, per ADR-015)
- Environment: local Windows 11, owner PC, RTX 5090. This is **not** the GTX 1650 target. Godot 4.7.2.stable.official.ed1daf0bf,
  Compatibility renderer.
- Content and rules revisions: unchanged. Tunables are in `assets/design/dispatch_stage_look.json` (project-owned,
  original), not `content/`. No third-party asset, font or texture was added.

## Diagnosis (why Alder looked good and dispatch did not)
| Alder Street (DS08, approved) | Dispatch stage before |
|---|---|
| Stormglass night sky, moon, fog, filmic tonemap, rain | One flat directional daylight on a grey void |
| Stormglass surface shader (brick, render, metal, asphalt, wetness) | Bright, untextured StandardMaterial3D in per-level hues |
| Detailed cabinets: plinth, cap, seams, handle, plate, hazard stripe | Every host target a bare 0.75 x 0.43 m grey slab |
| Lamps, kerbs, boundary wall, skyline | 52 m open plane, nothing framing it |
| Grounded geometry | EXP014 cabinets floating 1.4 m up; EXP017 "entry rise" plates stacked vertically at every station; walkway spans at eye height |

## Fix: `scripts/world/dispatch_stage_look.gd` (called once from `expedition_mission_stage.gd`)
1. Reuses `street_look.gd`: the same environment, moon and rain as Alder Street. The old fill light is turned down.
2. Re-skins static geometry with the Stormglass shader. Landmarks use Alder's own building palettes. Other layers keep
   their hue at night values. Groups whose materials change at runtime are not touched: task anchors, supply lights,
   feedback and approach routes.
3. Replaces each host target slab with a typed unit in the Alder cabinet language. The type comes from the authored ID:
   meter, switch, console, board, depot crate, junction box, or a relic plinth. Each unit faces out from its station hub.
   Targets that an EXP014 cabinet already dresses get no second unit.
4. Stands the EXP014 assemblies on the ground. Hides the zero-run EXP017 ramps. Lifts the walkway spans to 2.6 m and
   extends their pylons, so they read as an overhead gantry.
5. Adds one warm crew work light per station (tripod, on the approach side), four Alder-spec street lamps along the
   path, a boundary wall around the yard, and a dark skyline with a few lit windows.

Presentation only: none of it collides (tested). Aim and host checks use host positions, not these meshes. No host target,
position, text or state changes.

## What was run
- `--filter=DS_DISPATCH_LOOK` (`tests/integration/test_DS_dispatch_look.gd`): 4 passed, 163 assertions (LV_001, LV_077, LV_200).
- `--filter=EXP_DECLUTTER`: 2 passed.
- Full suite on this PC (all EXP and DS filters included): 1079 passed, 0 failed.
- Windowed 1600x900 screenshots on this PC (scratch tour scripts, not committed).

## Observed result
- `DS-dispatch-look/reference_alder_street.png`: the Alder Street reference frame (lookdev, DARK fake state).
- Before: `EXP-dispatch-label-declutter/after_LV_077_5p5m.png` (flat daylight, grey slabs, yellow walls).
- After: `DS-dispatch-look/after_c_LV_077_wide.png`, `after_c_LV_001_wide.png`, `after_c_LV_200_wide.png` (night works
  yard, lamps, wall, skyline); `after_c_LV_077_hub1.png` and `after_c_LV_077_hub3.png` (grounded cabinet, green post-mounted units
  with plates and hazard stripes); `after_d_LV_*.png` (the in-game first frame with the HUD).

## Not verified / pending_local
- Taste: one agent judged these against the Alder frame. The owner has not reviewed them yet.
- Frame time on the GTX 1650 target: not measured. This adds 5 omni and 4 spot lights (no shadows), about 25 unit nodes
  per station and a full-screen rain volume, all already used in C01.
- The dispatch levels are still procedural schematic sites. Reaching true Alder quality (authored facades with windows,
  kerbs, signs per site) means authored kit layouts, which is CT/D milestone work and outside this fix.
- Station signage is still large and wordy (the EXP layers' text). The label declutter only stops overlap.

## Resume notes
Committed on the branch above with the label declutter. The next step is owner review of the after frames.
