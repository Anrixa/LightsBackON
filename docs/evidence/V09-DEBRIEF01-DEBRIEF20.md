# V09 prep — DEBRIEF01–DEBRIEF20: authoritative completion debrief

**Scope:** twenty ordered, production-backed improvement and regression subphases for the C01 end-of-shift results screen, continuing the SOLO01–SOLO20 and FIELD01–FIELD20 batches. These are **not** original blueprint tasks and do not promote V09, D02 or any of the 66 roadmap entries.

**Authority:** debrief reads the frozen `MissionDirector.results()` receipt. It cannot alter stars, cash, rewards, power, grid inspection, mission completion, the offline checkpoint schema, or Steam transport. HUD objectives and hints are unchanged. Actual GPU/controller acceptance and two-network Steam remain pending.

| Phase | Change / coverage |
| --- | --- |
| DEBRIEF01 | No fabricated scores for incomplete runs. |
| DEBRIEF02 | Completed receipts enable a real scorecard. |
| DEBRIEF03 | Preserve host-authored stars rather than recalculating. |
| DEBRIEF04 | Bound displayed star totals defensively. |
| DEBRIEF05 | Show required-service numerator and denominator. |
| DEBRIEF06 | Bound displayed progress when receipt data is unexpected. |
| DEBRIEF07 | Base restoration award is separately explained. |
| DEBRIEF08 | No-optional-service contracts correctly award the optional star. |
| DEBRIEF09 | Incomplete optional work visibly misses the bonus. |
| DEBRIEF10 | Full optional restoration earns the bonus. |
| DEBRIEF11 | Sorted, unique optional service identifiers. |
| DEBRIEF12 | Unsafe or malformed optional identifiers excluded from UI. |
| DEBRIEF13 | Missing optional-service evidence never implies completion. |
| DEBRIEF14 | Tutorial allowance does not masquerade as a preventable trip. |
| DEBRIEF15 | Preventable trips explain the missing safety award. |
| DEBRIEF16 | Recoveries and equipment return come from frozen receipt. |
| DEBRIEF17 | Show host simulation time in minutes:seconds.tenths. |
| DEBRIEF18 | Time rolls over minutes without rounding errors. |
| DEBRIEF19 | Read-only immutable projection; keyed/pseudo-localizable text. |
| DEBRIEF20 | Actual Results scene integration, scrolling and focused controller exit. |

## Implementation

- `scripts/gameplay/shift_debrief.gd`: pure completion-only presentation; no calls into simulation, transport, persistence or UI renderer.
- `scripts/gameplay/mission_root.gd`: a 3-award scorecard, summary, optional-service context, exact host-tick clock and existing recorded diagnostics in the **real** scrollable Results panel. No new modal, gameplay timer or focus trap.
- `content/ui/strings/en.json`: keyed English text, pseudo-locale inherited from `UiText`.
- `tests/integration/test_DEBRIEF20_results.gd`: twenty individual tests, including a real scene instantiation and nonmouse exit focus.
- QA scope remains headless and does **not** claim a rendered Windows/GPU playthrough.

## Verification

Initial source head `be8f9b7633d77eee7f2e7200f754c026e2b55d81` passed the complete GitHub-hosted Linux/Windows pipeline ([run #42294843054](https://github.com/Anrixa/LightsBackON/actions/runs/42294843054)): **418 Godot tests, zero failures, 9,340 assertions on each runner**, C01 solved in 316 ticks (56 steps), Python reference cross-check MATCH (32 cases / 246 command hashes / 10 invalid-definition rejections), QA57 tracked-UID gate PASS, signed-source pin/export-preflight PASS, Windows release export, headless exported-EXE smoke and artifact upload PASS.

A targeted QA55 real-results ownership test has subsequently been added to exercise panel/label teardown through the dedicated QA51 resource probe. **Final source-head Linux/Windows CI, QA51 resource probe and post-merge main CI are pending at this documentation checkpoint**. A headless export is not a real graphics launch.

## Resume

After verified CI, conduct physical Windows GPU/controller readability checks at 720p/150% UI scale, play C01 through to real results, inspect a saved completed checkpoint, and perform required Steam two-network verification separately. V09 stays NOT_STARTED; F02 remains BLOCKED.
