# ADR-017: Design, UX and content work goes ahead of the F02-blocked network gates

- Status: **Accepted**, 9 Nov 2026, on the owner's mandate (quoted in ADR-016 section 6) and the owner's answers in the design session the
  same day. Revisit when F02 is unblocked (second Steam account) or if the owner wants the old order back.
- Amends CLAUDE.md section 6 step 2 ("do not start art or content while the current interaction/network model is unproven").
  Builds on ADR-011 and ADR-015 (work continues while F02 is blocked) and ADR-016 (engine stays, lookdev approved).
- Changes no locked decision (CLAUDE.md section 1) and no network honesty rule (sections 4 and 8).

## Context

- F02 has been BLOCKED since 29 Oct 2026 (no second Steam account). 18 tasks are parked behind it, and the backlog's next art tasks (A01, D01,
  DS03) sit behind V09, which sits behind F02. With the old rule, no world art, lookdev or new content could start at all.
- The owner judges the product by what is on screen and called the current look "extremely poor". The UI is real and tested
  (V07, F05, DS01/DS05). The world is a graybox with debug-ID signs and no art (ADR-016 section 1).
- QA140 measured the graybox on a real GTX 1650, Radeon RX Vega 10 and Intel UHD: about 4x frame-time headroom under the Compatibility
  renderer. The GPU budget for art exists.
- The grid, repair, mission, save and reward logic is headless-tested and is what the look must present. Presentation already reads host
  state (`scripts/world/restoration_presentation.gd`, DS04).

## Decision

1. **Design-first order while F02 is blocked.** Desktop sessions work the design workstream in `docs/design/DS07-design-plan.md`
   (task IDs DS07 onward, tracked in `docs/design/quality-workstream.json`) ahead of the parked network tasks. The order inside it is
   player-facing value first: the C01 first minute and the world look, then the three pillars, then input glyphs and polish, with content
   in parallel (point 3).
2. **The look may dress the mission scene.** ADR-016 decision 4.1 kept the lookdev spike out of `mission_root`. That limit stays for anything
   that fakes state: fake supply states live only in `scenes/lookdev/` and are labelled. The reusable look itself (environment, materials,
   weather, dressing props, diegetic signs) reads only host state and may be used by the mission scene once it passes all of these:
   - the full suite (`bash tools/run_tests.sh`) and both CI jobs;
   - rendered HUD contrast still **224/224** (`tools/godot/capture_hud.gd`, ADR-016 section 5.5);
   - a three-state screenshot set at 1920x1080 (dark, temporary, restored) in `docs/evidence/img/`;
   - P95 frame time and memory from an internal export with the QA140 harness on at least one GPU from the QA140 set. The Intel UHD on the
     owner's PC is the slowest of the three and counts as the conservative check. The GTX 1650 laptop is used only after the owner confirms
     it is free (another project's session shares it; see QA140).
   - Collision, gameplay node paths, stable IDs and contract data do not change; dressing is visual only. Look data lives under
     `content/` (no magic numbers in code), so it changes the content revision like any content edit; peers on the same build
     still match. Offline checkpoints written by an older content revision are refused with CONTENT_MISMATCH and preserved
     (ADR-008 behaviour, found in DS08); keying checkpoints on gameplay content only is a follow-up, not decided here.
3. **Contracts C02-C12 may start now as logic and data** (owner's answer, 9 Nov 2026: "In parallel, logic only"). Grid, mission, repair,
   equipment and solution-trace data, replayed by `tools/godot/validate_solution.gd`, following the contract authoring checklist
   (blueprint p.21). Art for them follows the approved C01 look. They reuse the graybox until then. No contract counts as qualified (CT
   tasks keep their dependencies and statuses).
4. **Design approval.** The owner hired Claude as the main design artist and developer and delegated approval of project-made design work.
   Claude approves the lookdev look as lead designer, then starts the project design agent (`.claude/agents/lbo-design-artist.md`) for
   element design. The owner still decides: third-party assets (licence recorded first), money, locked decisions, the cut order, the
   public game name, and anything on the CLAUDE.md stop-and-ask list. The deferred owner reviews in `docs/PC-WORK.md` section 5 stay open
   until the owner looks.
5. **Backlog statuses do not move because of design work.** A01, D01, DS03 and V09 keep their dependencies, and nothing becomes DONE without
   its own acceptance. Design work is recorded under DS IDs with evidence files. When A01/D01 eventually run, they start from this work.

## Guardrails

- **State honesty:** presentation reads host snapshots only (window glow, signs, lamps, sounds). Clients never decide supply.
- **Pillar 1:** no world cue may reveal the exact repair. A sign may say a building has no power; it may not say which fuse failed.
- **Renderer:** Compatibility only (owner, 9 Nov 2026). No SSR, SSAO, SDFGI or volumetric fog. Budget targets (to test, not facts):
  GTX 1650 1080p P95 at most 8 ms; Intel UHD at most 14 ms at its native 2560x1600; no load stall over 1 s without a loading screen.
- **Accessibility:** Reduce Flashes and Reduce Camera Motion cover every new effect; status always icon + text; recovery readable without
  audio and without darkness hiding the scene (pillar 3).
- **Assets:** project-made only unless the owner approves a third-party source with its licence recorded (ADR-004 point 6). Shaders,
  procedural meshes and textures generated by project code are project-made.

## Consequences

- The playable slice will look and read much better before it is network-qualified. The network risk (F02) is unchanged and still the
  biggest product risk; nothing here hides it.
- Look changes can break HUD contrast or frame time; points 2 and the guardrails make both measured on every look change.
- If F02 later forces an engine re-evaluation (ADR-016 section 2.3), project-made shaders and dressing code are Godot-specific; the
  design decisions, layouts, palettes and content data carry over.
