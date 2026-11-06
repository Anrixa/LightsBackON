# FIELD01–FIELD20: live shift awareness in the playable C01 HUD

**Scope:** twenty ordered, implementation-backed improvements under preparation for V09 (the playable slice gate). These are **not** twenty completed original blueprint tasks. They add a compact, read-only shift/timer status beneath the three authored objective chips in the existing S06 HUD instead of creating a competing floating overlay.

**Authority boundary:** the field view is projected from the existing host-authored C01 objective states, latch, 10 Hz verification and departure countdown. It neither sends player commands nor changes power-grid, repair, mission, save, reward, transport or Steam contracts. Hidden/upcoming objectives cannot expose timer details. No uninspected fault cause or topology detail appears in the HUD.

| Increment | User-facing behavior / regression |
| --- | --- |
| FIELD01 | Live objective fraction comes from C01's six authored objectives. |
| FIELD02 | Show status during an active solo shift. |
| FIELD03 | Localize the current restoration phase. |
| FIELD04 | Hide future timer readings while their objectives are not active. |
| FIELD05 | Active basement-drain objective displays a zero-origin meter. |
| FIELD06 | Drain progress reads the host-authored 120-tick latch. |
| FIELD07 | Clamp progress to 100%. |
| FIELD08 | Completed drain does not show a stale draining bar. |
| FIELD09 | Active grid-verification objective displays a zero-origin meter. |
| FIELD10 | Show host-calculated verification progress. |
| FIELD11 | Reset the bar on lost continuous supply. |
| FIELD12 | Verified supply switches to the equipment-stow phase. |
| FIELD13 | Stowed equipment still requires returning to the van. |
| FIELD14 | Returning to the van does not bypass stowing equipment. |
| FIELD15 | Ready status only after verification, stow and van presence. |
| FIELD16 | Countdown seconds derive solely from remaining authoritative ticks. |
| FIELD17 | Departure progress derives from the existing five-second contract. |
| FIELD18 | Cancelling departure immediately hides the obsolete countdown. |
| FIELD19 | Mission completion hides live controls; projection does not mutate host state. |
| FIELD20 | Production OfflineC01Session, real MissionRoot HUD and accessibility-scale/pseudo-locale rendering are integrated. |

## Implementation

- `scripts/gameplay/shift_operations.gd`: new pure `field_view()` projection constrained to currently visible/active objectives.
- `scripts/gameplay/offline_c01_session.gd`: real `hud_view()` includes `field_shift` sourced from existing `shift_operations_view()`.
- `scripts/ui/field_hud.gd`: one existing objective-card status line and an optional noninteractive progress bar; focus/mouse input stays available to the existing player controller and overlays. Silent mission ticks update only the existing label/bar in place, never tear down the HUD tree.
- `scripts/gameplay/mission_root.gd`: display the new host-tick progress independent of sparse mission events; the host runs at 10 Hz while playing and is frozen by the existing pause.
- All currently visible active objectives are considered for timer presentation (not just the first active text key). Hidden objectives still cannot expose future status.
- `content/ui/strings/en.json`: localizable English keys (pseudo locale supported by the existing text system).
- `tests/integration/test_FIELD20_live_status.gd`: twenty separate production-path regressions and real scene smoke.

## Verification and gates

- Source baseline: `main` `c905828cabc42ea71db7f9110f5c071d75cdb836` (PR #117 merged with successful main CI).
- Production implementation head: `7dbd8d014f9e2d994d3dd9052664519c371c9ee4` (PR #118).
- [Linux + Windows full CI #42288524045](https://github.com/Anrixa/LightsBackON/actions/runs/42288524045): **PASS** on both runners, 398 Godot tests, 0 failures, 9,279 assertions each; the existing C01 replay/reference checks passed. On Windows the QA57 tracked UID check, pinned Godot 4.7.2 Windows release export, exported EXE headless smoke, build-manifest verification and artifact upload passed. No actual GPU or controller was exercised.
- [QA51 isolated resource probes #42288524241](https://github.com/Anrixa/LightsBackON/actions/runs/42288524241): **PASS** on Linux/Windows; zero observed CanvasItem/ObjectDB/DummyTexture/ShapedText/FontRID deltas in the isolated diagnostics.
- Subsequent code review identified two live-game defects that headless static projections did not expose: progress ticks did not always generate events, and the first active objective could mask a second visible active pump objective. These have been corrected in the same PR; the final amended source commit needs exact-head CI and post-merge main CI before claiming integration.
- Runtime physical GPU, actual controller interaction, readable UX at 720p/150% with a person, solo C01 run counts, two-network Steam join and V09 gate: **NOT RUN**.
- Original 66-task `docs/backlog.json` is unchanged. F02 remains BLOCKED; V09 remains NOT_STARTED.

## Resume notes

Do not merge without exact-head Linux/Windows, export/headless smoke and QA51 results. Verify postmerge main independently. A real controller and real GPU visual inspection remain mandatory for game-acceptance; automated layout and locale assertions alone are not acceptance evidence.
