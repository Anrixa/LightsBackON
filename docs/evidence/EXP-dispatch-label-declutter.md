# Evidence: EXP dispatch-stage label declutter (presentation only)

- Status claimed: fix merged with tests; no backlog status change (this is a defect found in the v0.21.0 playtest, not a backlog task)
- Date (UTC): 2026-11-23
- Branch: task/EXP-dispatch-label-declutter (cut from origin/main a1cffca)
- Environment: local (Windows 11, owner PC, RTX 5090; not the GTX 1650 target), Godot 4.7.2.stable.official.ed1daf0bf
- Content revision: unchanged; no file under `content/` was touched. Host rules, protected blobs, saves: untouched.

## Defect
In the experimental field dispatch stage, several independent layers each label the same station: host target labels,
EXP014 worksites, EXP017 region/site signs, EXP019 task anchors and EXP020 placards. About 15 Label3D signs sat within
2.4 m of station 01. Five of them stacked in one column at overlapping heights, and billboards at different depths
overlapped on screen through perspective. Screenshots of LV_001, LV_077 and LV_200 from the playtest showed the first frame
covered in overlapping text (severity P2: wrong feedback with a workaround, because you could walk away).

## Fix
`scripts/world/expedition_label_layout.gd` (new) runs once when the stage loads (`expedition_mission_stage.gd`):
1. Device labels (`WorksiteLabel`, one per host target) are hidden and shown only for the device under the reticle. This is
   the usual focus-reveal pattern, and the HUD `Target:` line already names that device. Plates and geometry stay visible,
   so devices are still discoverable. If a device label would overlap a station sign, it is drawn under its plate instead.
2. All other visible labels within 1.6 m of each other on the ground plane are re-stacked from the bottom up on one shared
   vertical axis, with a 0.08 m gap. That makes one readable column whose boxes cannot overlap from any viewing angle.

It only changes `Label3D.visible` and label positions. It never changes text, colliders, target positions or host state.

The spawn backoff (5.5 m) and the HUD backdrop card are in PR #306 (SAVE23 / v0.21.0). The screenshot here simulates
that spawn by moving the player 3.8 m back from the 1.7 m spawn on this branch.

## What was run
- `"$GODOT_BIN" --headless --path . -s res://tests/run_tests.gd -- --filter=EXP_DECLUTTER`: 2 passed, 334 assertions.
  - `test_EXP_DECLUTTER_station_signs_share_a_column_without_overlap` (LV_001, LV_077, LV_200): every pair of visible signs
    in a cluster shares the axis and has a gap of at least 0.08 m.
  - `test_EXP_DECLUTTER_device_labels_reveal_only_the_aimed_device`: all device labels start hidden, an aim reveals only
    that device's label, and an empty target hides them all.
- Regression filters EXP03, EXP04, EXP017, EXP019, EXP020, EXP021: see the results section in the PR.
- Windowed 1600x900 screenshot tour (scratch script, not committed): `after_LV_077_5p5m.png`.

## Observed result
`EXP-dispatch-label-declutter/after_LV_077_5p5m.png`: from 5.5 m the station reads as a single column (WORKSITE A,
LOAD_A / DARK, MEZZANINE / WASHOUT, JOB_077_1, FIELD WORK ORDER block) with no text-on-text overlap. World geometry (the
pillar and the plate) still hides parts of some signs. That is depth-correct occlusion, not a layout overlap.

## Not verified / pending_local
- Legibility judged by one agent from screenshots, not by people; text size at 1080p on a 1650-class GPU was not checked.
- The signs are still physically large up close (graybox signs about 0.45 m text height). Shrinking per-layer sign sizes is
  left to the DS art pass, so the authoring layers keep their own tests.
- Controller aim reveal has not been checked on a real pad (same aim path as the mouse).

## Resume notes (for the next session)
Committed with tests on the branch above. If PR #306 merges first, merge main into this branch and rerun the EXP filters.
