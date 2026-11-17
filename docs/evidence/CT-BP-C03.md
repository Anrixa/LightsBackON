# CT-BP/C03 Roof Route — source-fidelity corrective implementation evidence

- **Date:** 2026-11-17. **Status:** **SOURCE_ALIGNED_HEADLESS_CANDIDATE**, not original-blueprint physical certification.
- **Authority:** Development Blueprint v1.0 p.19, ADR-017 and the confirmed C03 mismatch in `docs/design/CT-BLUEPRINT-CORRECTIONS.json`.
- **Base main:** `300703ef494d19ee045efa5bcae459d5673d8e58` (post C02 correction).
- **Branch:** `task/CT-BP-C03-roof-route-correction`. **PR:** [#166](https://github.com/Anrixa/LightsBackON/pull/166) (draft pending final documentation-head verification).
- **Source implementation head:** `1451efa0a5126b9f4a9170be99666858c2356237`.
- **Verified source CI:** [#44034573394](https://github.com/Anrixa/LightsBackON/actions/runs/44034573394); Linux and Windows success on tested source head.

## Implemented and replayed

C03 now starts with a failed/tripped west fuse. Meter-first `R_JW_FUSE` restores west GRID supply; the 1 PU west-powered ladder access light must then hold 50 consecutive valid ticks before an authorized roof-ladder receipt. `R_ROOF_SPLICE` repairs the roof bypass, `SW_ROOF_FEED` enables the initially disabled 12 PU roof feeder (11 PU required east load), and the damaged direct east feeder stays broken. The safe full solution draws 21 PU total from GRID: west 10/12 and roof 11/12. Wrong west crossfeed trips after overload.

The optional roof work light keeps legacy entity ID `ROOF_BEACON` for preview compatibility but is corrected to **2 PU on GEN**, not a 1 PU GRID beacon. GEN-to-light route is separate. Bonus latches only after 100 uninterrupted, valid GEN-supplied ticks. Missing it does not block extraction or required restoration. C03's solved trace consists of 58 steps, reaching completion in **250 host simulation ticks** (not a timed human playthrough). UI localization now describes the ladder and work light, and the network tablet includes the ladder-light node.

C03-only host authority adds source-qualified latches, ladder precondition and completed-latch reward; original C01/C02 content is byte-preserved. Restore validation refuses invented/missing/inconsistent counters and ladder IDs without altering the loaded state. Earlier released C03 checkpoint compatibility has not been approved or migrated; the C03 preview remains no-save.

## Actual CI and falsification history

| Run and source | Linux | Windows | Result |
| --- | --- | --- | --- |
| [#44033910551](https://github.com/Anrixa/LightsBackON/actions/runs/44033910551), initial head `211a8bceddae6be6417845d5f86623c4cd664aa7` | 646 tests passed, **2 failed** | Initial job superseded | Initial failures were test expectations for first objective (new ladder task) and Godot's parsed float JSON numbers; valid host solution still SOLVED 250 ticks. Not qualification evidence |
| [#44034278793](https://github.com/Anrixa/LightsBackON/actions/runs/44034278793), corrected tests `97bdd555f0eb255677e5cccf709d8fc4f4c4f2b7` | Passed | Superseded/cancelled on later branch push | Intermediate evidence only |
| [#44034573394](https://github.com/Anrixa/LightsBackON/actions/runs/44034573394), final implementation source `1451efa0a5126b9f4a9170be99666858c2356237` | **650 passed, 0 failed, 47,588 assertions** | **650 passed, 0 failed, 47,588 assertions** | Both platform jobs green |

- Content validator: **85 JSON files, 0 errors** on Windows; Python, authoring and syntax checks passed.
- Actual solution replay: C01–C08 all **SOLVED** on Linux and Windows; C03 **250 ticks / 58 steps**.
- Python/Godot reference comparison: **MATCH** — 32 forward/reverse case runs, 246 command hashes, 10 definition rejections, identical content hash. Reference is re-derived and is not an independent copy of the original blueprint oracle.
- Windows pipeline: Godot 4.7.2 export templates, script UID validation, EXE/PCK release export and headless launch smoke succeeded; **QA57_EXPORT_PREFLIGHT=PASS** on GitHub Windows runner. This is not a target GPU performance benchmark.
- Tests cover exact 50/100 tick boundaries, same-tick light loss, optional omission, unsafe crossfeed, ladder refusal/host distance, forged save rejection, invalid authoring and C01/C02 legacy state. The existing C03 physical preview test verifies no teleport before host approval.

## Open gates

1. Exact **documentation PR head** Linux and Windows revalidation, successful merge, and post-merge main CI.
2. Actual Windows GUI/controller/human walkthrough of C03 preview; a usable visible roof-feed switch and optional generator/socket flow; scene presentation, onboarding and no-save boundary.
3. Target-class exported GPU frame-time P95, memory and 720p/1080p visual/contrast/accessibility review; C03 old-release save compatibility decision.
4. F02/F06 two-real-network Steam acceptance and official `docs/backlog.json` CT03 D08 dependency. Original-blueprint full certification remains **HOLD**. No destructive cleanup, migrations or release promotion.
