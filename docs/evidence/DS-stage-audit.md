# Evidence: DS stage audit: every playable area checked (owner request, 23 Nov 2026)

> "Every single stage and level and playable area should be checked and accurately designed!" (owner)

- Date (UTC): 2026-11-23
- Branch: task/EXP-dispatch-label-declutter (with the dispatch look and the label declutter; one PR, not stacked)
- Environment: local Windows 11, owner PC, RTX 5090 (not the GTX 1650 target), Godot 4.7.2.stable.official.ed1daf0bf
- Content and rules revisions: unchanged (`content/` was not edited). Saves untouched.

## What counts as a playable area (inventory)
| Area | Scene | How it was checked |
|---|---|---|
| Main menu | `scenes/menu/main_menu.tscn` | 1600x900 screenshot |
| Dispatch atlas | `scripts/ui/dispatch_atlas_panel.gd` | 1600x900 screenshot |
| C01 Alder Street (First Shift) | `scenes/mission/mission_root.tscn` | 4-direction screenshots at spawn; end-to-end input bot (PR #307, now in CI) |
| C03 Roof Route preview | `scenes/mission/c03_roof_preview.tscn` | 4-direction screenshots |
| C04 The Whole Block preview | `scenes/mission/c04_sign_spur_preview.tscn` | 4-direction screenshots |
| 200 dispatch levels LV_001-LV_200 | `scenes/expeditions/mission_stage.tscn` | automated scene audit on **all 200**, plus spawn and wide screenshots of **all 200** |

C02 and C05-C12 have contract logic and data but no playable scene yet, so there is nothing to walk.

## Automated audit: `scripts/diagnostics/stage_audit.gd`
For each built stage it checks:
- **floating geometry**: a part counts as supported only if a chain of touching parts reaches the ground;
- **out-of-bounds** props;
- **host targets buried** in a collider;
- **stations enclosed** by a building volume;
- **spawn**: inside the site, not in a collider, not inside a mesh-only building, and a clear view of station 01.

A control test lifts a cabinet off the ground and expects a finding, so the audit cannot pass vacuously.

| Run | Levels failing |
|---|---|
| First run (support from below only) | 36 / 200 (turbine housing, truss brace) |
| Support traced through connected parts, fewer exemptions | 183 / 200 (canopies with no columns, hovering awnings, crossarms missing their legs, busbars, roof slabs) |
| After the geometry fixes below | 0 / 200 |
| Spawn and enclosure checks added | 112 / 200 (a station inside a landmark building; spawn facing a wall) |
| After the landmark-placement and spawn fixes | **0 / 200** |

## Defects found and fixed
1. **Floating parts** (fixed at the source, where each shape is built):
   - EXP014 busbar: now sits on its cabinet.
   - Rack control top, shed/vent/hoist roof slab, lift post and exhaust: now rest on the part below.
   - Canopy roof and gantry head: now rest on the span.
   - EXP017 turbine housing: now on a plinth.
   - Truss brace: now reaches the ground.
   - Graybox market and relief awnings, school bell and feeder: now sit on their buildings.
   - Mast crossarm: two arms, one per leg row.
   - Platform canopy: now has columns.
2. **Stations inside buildings (112 levels).** Landmark buildings were placed at fixed coordinates while stations vary per
   level, and landmarks are walk-through. `expedition_graybox.gd` now slides each landmark by the smallest offset that
   keeps it 3 m clear of every station and the route between them.
3. **Spawn.** A fixed "+5.5 m on Z" spawn faced a wall or stood inside a building on about half the levels, and was clamped
   into the sign stack on LV_161-195. `scripts/world/dispatch_spawn.gd` now picks a clear spot with a view of station 01,
   preferring the approach from behind, and faces the player at it.
4. **Dispatch look** (`docs/evidence/DS-dispatch-look.md`): the Alder Stormglass look, typed equipment units, grounded
   cabinets, hidden zero-run ramps. The yard asphalt is now drier, because Alder's wet street read as black holes over 52 m.
5. **C03/C04 notice.** The development-preview message was bare text over the street and overflowed its 50 px box. It
   now sits in the HUD card and sizes to its text (`mission_root.gd`).
6. **Meter LCD.** The "? NOT MEASURED" readout had Label3D's default black outline, which smeared the dark LCD text. The
   outline is removed.
7. **Atlas preview.** A 78 m orthographic frame drew the 52 m site as a thumbnail in a grey box. The frame is now 46 m,
   taller, and has a transparent background.

## What was run
- All 200 levels: audit runner (scratch script around `stage_audit.gd`), 2 processes, headless. Final result: 0 failures.
- `--filter=DS_STAGE_AUDIT`: 50 sampled levels plus the control test pass. With `LBO_FULL_STAGE_AUDIT=1` it covers all 200.
- Screenshots of all 200 levels (spawn and wide) at 800x450. Sheets: `DS-stage-audit/spawn_sheet_*.jpg`;
  before: `before_spawn_sheet_001.jpg`.
- Full suite `bash tools/run_tests.sh` on this PC: exit 0, **1079 passed, 0 failed**, 498,573 assertions. Python: 476 OK.

## Not verified
- Looks were judged by an agent from screenshots, not by people. Owner review is pending.
- There is no navmesh walk of every dispatch level. Completability by real input is proven for C01 only (PR #307 bot).
  The dispatch levels remain "EXPERIMENTAL / NO PLAYABILITY CERTIFICATION", as their own UI says.
- Mesh-only landmarks are still walk-through. Giving them collision would change line of sight to host targets, which
  is a host-behaviour change for its own task.
- Station signage text is still dense. The overlap is fixed, but the wording is EXP-layer content.
- Not measured on the GTX 1650 target.
