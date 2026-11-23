# Evidence: SAVE23 v0.21.0 windowed playtest and fixes

- Status claimed: fixes merged; no backlog task status changed (all affected tasks stay CLOUD_VERIFIED or parked on F02 / people)
- Date (UTC): 2026-11-23
- Branch: `task/SAVE23-playtest-v0.21.0`, based on `main` at `a1cffca` (PR #304, EXP019-EXP021 integration)
- Environment: owner's Windows 11 PC (local desktop session), NVIDIA GeForce RTX 5090 Laptop GPU, driver 621.24, OpenGL 3.3 Compatibility.
  This is **not** the GTX 1650 performance-target class; no frame-time claim is made here.
- Engine: Godot 4.7.2.stable.official.ed1daf0bf (editor console binary, not an export)
- Version: `application/config/version = 0.21.0` (first version string in the project; no git tag, per the EXP019-EXP021 integration record)

## What was run
All windowed runs used a temporary `override.cfg` (custom user dir) so the owner's real profile was never written; the file was deleted
before committing. Drivers were scratch `-s` scripts that use only the real input path (`InputEventAction`, `Input.action_press`) and the
real menu buttons.

1. `--ds09-first-reading` against the owner's real profile: exit 3 `start_unavailable` (defect 1 below).
2. Same driver with an isolated profile: `DS09_FIRST_READING ok start_to_playable_ms=6454 playable_to_reading_ms=7847`.
3. Tour of every main-menu entry point with screenshots: C01 (walk, tablet, pause), Roof Route preview, Whole Block preview, dispatch atlas,
   dispatch LV_001 (walk, field tablet). No engine errors in any scene.
4. Label probe of dispatch LV_001 / LV_077 / LV_200 (nearest visible Label3D to the camera at spawn, floor contact).
5. Archive flow against a **copy** of the owner's stranded checkpoint (copied into the isolated profile; originals untouched and re-verified
   by `cmp`).
6. `bash tools/run_tests.sh` on the final tree (result below) and focused runs of `test_G06_offline`, `test_DS01_menu`, `test_DS13_input`,
   `test_EXP03_stage`, `test_EXP04_stage`.

## Defects found and fixed
| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | P1 (mission cannot start) | A checkpoint from older mission rules (no `rules_revision`, ADR-018 rule 5) reports `CONTENT_MISMATCH`, which disabled **Continue and New Solo Shift**. C01 was unplayable on the owner's PC with no in-game way out. | Owner-approved: New Solo Shift stays enabled, explains the outdated save, confirms, then `archive_mismatched_checkpoint()` moves `SOLO_C01.json` + `.bak`/`.tmp` to `checkpoints/archived/SOLO_C01-<UTC>.json`. Corrupt / newer-schema saves unchanged. ADR-018 amendment. |
| 2 | P2 | Network tablet **Close** (and Ping) caption slid under the overlay key glyph ("Tab]lose"). | Button reserves the glyph footprint with a transparent icon, so text and minimum width account for it at every scale/device. |
| 3 | P2 | Experimental dispatch spawned 1.7 m from station 01, inside ~15 stacked host labels: first frame was unreadable text. | Spawn 5.5 m back (clamped to the floor); nearest label at spawn 4.2 m on LV_001/077/200, player on floor. |
| 4 | P2 | Dispatch HUD text had no backdrop (unreadable on the light graybox); Return button stretched across mid-screen. | HUD on a bounded tinted card; Return is a normal-width button. |

Screenshots: `docs/evidence/SAVE23-v0.21.0-playtest/` (before/after pairs).

## Tests added
- `test_G06_content_mismatch_checkpoint_archives_without_deleting`, `test_G06_only_content_mismatch_is_archivable`
- `test_SAVE23_outdated_checkpoint_offers_archive_instead_of_dead_end` (menu, including the version label)
- DS13 tablet test: Close/Ping reserve their glyph width

## Observed result
Full suite: see the PR's CI and the "Full suite" line below.

## Not verified / pending
- No exported build was profiled; no GTX 1650 P95 frame time.
- Human / controller feel, Steam (F02/F06), co-op: unchanged and still outstanding.
- Dispatch stations still stack many co-located labels when the player walks up to them (handled in the follow-up branch).

## Resume notes
Merged as one PR. Follow-ups continue on separate branches (C01 physical playthrough bot, results-screen HUD cleanup, dispatch label declutter).
