# ADR-016: Engine assessment and visual-hardening instructions

- Status: **Accepted** (8 Nov 2026 in part; section 4 decided by the owner on 9 Nov 2026, see section 6). Sections 1-3 and 5 are accepted
  guidance. Section 4 decision 1 is approved, decision 2 is resolved (Compatibility stays), decision 3 is answered (Claude is the designer).
  The design-first re-ordering that follows from this is ADR-017.
- Trigger: owner review of the RTX 5090 renders (QA138): "design obviously needs hardening. Is this all that we can achieve by Godot?
  Is it the best engine for this project?"
- Changes no locked decision by itself. Clarifies CLAUDE.md sections 1, 6 and 7, ADR-004 and `docs/design/quality-workstream.json`.

## 1. Why the game looks like this today

What the owner saw (`capture_district_views.gd`, `capture_hud.gd`, the C01 mission scene) is a **graybox**, not a finished look and not the
engine's limit:

- untextured boxes from `scripts/world/kit_builder.gd`, one sky colour, one light, no fog, rain, decals, props, characters or hands;
- raw debug IDs as `Label3D` signs (`APT_W`, `JW`);
- window glow added by the capture tools only (the presentation layer that drives real window states is not built yet);
- zero production art: no models, textures, materials, VFX or audio have been made or licensed.

This is deliberate. The backlog puts art behind the playable-slice gate: A01 (art benchmark street) depends on V09, DS03 depends on V09,
A01 and D01, and V09 sits behind the F02 Steam block. CLAUDE.md section 6.2 says not to start art or content while the interaction and network
model is unproven. The UI, by contrast, is real (V07, F05, DS01/DS05): tokens, icons, contrast, reflow and focus are tested.

## 2. Engine assessment: is Godot the right engine?

**Verdict: stay on Godot 4.7.2.** It is not the visual ceiling here. Re-open the question only at the decision point in section 2.3.

### 2.1 What Godot can and cannot give this game

The look in ADR-004 and DS01 ("Stormglass / Civic Revival": cool rainy blue-hour street, warm restored windows, honest dark/temporary/
grid states) is a stylized, compact, authored scene. Godot is capable of that. What limits the result is mostly **assets and art
direction**, then **renderer choice**:

| Lever | Effect on the look | Available in Compatibility? |
|---|---|---|
| Authored models, trim sheets, vertex colour, props, characters, hands | the largest single improvement | yes |
| Baked lighting (LightmapGI) + emissive windows + glow | warm-window-in-cool-street mood | yes for using baked lightmaps; verify the 4.7 baking workflow under Compatibility |
| Fog, authored rain VFX (particles, screen-space streaks), wet-surface shader tricks | storm identity | basic fog and CPU/GPU particles yes; **volumetric fog no** |
| SSAO / SSIL / SSR (wet street reflections), SDFGI / VoxelGI | depth and "next-gen" polish | **no** (Forward+ only) |
| Many dynamic lights per object | streetlamps, flicker on restore | limited per-object light count |

Feature support changes between Godot versions. **Check the Godot 4.7 renderer comparison page before relying on any row above**; it is
written from knowledge of 4.4-4.6 and was not re-verified for 4.7.

### 2.2 Alternatives, honestly

| | Godot 4 (current) | Unity 6 (URP) | Unreal Engine 5 |
|---|---|---|---|
| Visual ceiling for this art style | good with authored art; weakest built-in lighting | good; mature stylized/URP pipeline | highest (Lumen/Nanite), but those target hardware well above GTX 1650 |
| GTX 1650 / 4 GB fit | good (Compatibility or Mobile) | good | possible only with Lumen/Nanite off and careful scaling; large builds |
| Steam co-op networking | third-party GodotSteam; **this is the open F02 risk** | mature community Steam + netcode libraries | built-in Steam online subsystem and replication |
| Asset ecosystem | small | very large | large (Fab) |
| Cost and licence | MIT, free | free tier below a revenue threshold, paid seats above | royalty above a revenue threshold |
| Cost of switching now | none | rewrite of all GDScript (sim, host, save, UI, tests); Python reference survives | the same rewrite in C++/Blueprint, plus a heavier pipeline |

Licence terms are as of mid-2026 and were not re-checked; verify before any decision. A switch would cost months and would not create a single
art asset. The game's hard parts (deterministic grid, host authority, save integrity, readable co-op UI) are engine-independent and
already tested here.

### 2.3 Decision point (when to re-open)

Re-evaluate the engine **only if F02 fails**: if no GodotSteam build meets the transport tuple (P2P relay join, reconnect, two networks), compare
fixing it against moving to an engine with first-party Steam networking. Visual quality alone is not a reason to switch.

## 3. What "design hardening" means here

Two different jobs, kept apart:

1. **UI/UX hardening:** allowed now, cloud or local. Continue with the open items in QA138 section "Refinement plan", ADR-004 and
   `docs/PC-WORK.md` section 5: tablet default zoom, `unknown` token headroom, 150 % readability, controller run.
2. **World visual hardening (lookdev and art):** the 3D look. Gated (section 4, decision 1). It needs a real GPU and a desktop session, and
   eventually art made by a person or licensed assets.

## 4. Proposed owner decisions (not in force until approved)

1. **Allow a lookdev spike before V09.** One non-shipping scene `scenes/lookdev/alder_lookdev.tscn` with the existing 4 m kit and
   project-made materials only. It proves the lighting recipe in the three supply states (dark, temporary, restored) plus rain. Limits: no
   gameplay code changes, no kit expansion, no third-party assets without the stop-and-ask record, nothing referenced from `mission_root`.
   Why now: the F02 block may last, and renderer and pipeline choices must be settled before any content production.
2. **Renderer decision by measurement.** Keep Compatibility as the locked baseline. Build the spike so it runs under Compatibility and under
   Mobile/Forward+ (a project-setting override, nothing else). Measure P95 frame time and VRAM from an exported build on a **GTX 1650-class**
   machine. The owner then keeps Compatibility or amends the locked decision in a new ADR. The RTX 5090 can show the look but cannot
   decide this. First graybox data points on lower-tier GPUs (Intel UHD iGPU, Adreno 640) are in `docs/evidence/QA139.md`; exported-build
   P95/memory for Compatibility, Mobile and Forward+ on a real GTX 1650, Radeon RX Vega 10 and Intel UHD (graybox) are in
   `docs/evidence/QA140.md`, with the unattended harness to repeat them on the lookdev scene.
3. **Art production capacity.** Claude can write shaders, lighting, VFX, procedural materials, layout and capture tooling. It cannot produce
   production-quality characters, hands or hero props on its own. Decide between commissioning an artist and licensing a coherent asset kit
   (licence, source and version recorded first). Then A01/D01 can reach the ADR-004 bar.

## 5. Instructions for sessions doing visual work

Follow these with ADR-004 (quality bar, tokens, licensing) and CLAUDE.md:

1. **Check the gate first.** World art and lookdev only after section 4 decision 1 is approved (record the approval date here) or after V09 is
   DONE. Until then, do UI/UX hardening only. **Approved 9 Nov 2026 (section 6).** The gate is open; ADR-017 sets the order and guardrails.
2. **Local desktop session on the GPU.** Never claim a visual result from the cloud. Export with
   `bash tools/setup_export_templates.sh` (once per PC), then
   `Godot --headless --path . --export-release "Windows Desktop" build/windows/LightsBackOn.exe`.
3. **State honesty.** Presentation reads host state; a window glows only for a supplied consumer. Lookdev may fake states, but only inside
   `scenes/lookdev/`, labelled as fake in every screenshot caption and evidence file.
4. **Three-state screenshot set** for every visual change: dark, temporary (generator), restored, from the eye markers that
   `capture_district_views.gd` uses, at 1920x1080. Put them in `docs/evidence/img/` and add them to the evidence file.
5. **Contrast and readability.** Run `capture_hud.gd` after any scene lighting change. The HUD probes measure against the rendered scene, so a
   brighter or darker street can break AA. 224/224 probes must pass.
6. **Performance is measured, not assumed.** Report P95 frame time and memory from the exported build on GTX 1650-class hardware. Numbers from
   the RTX 5090 are labelled "high-end sanity check" (QA138 style). `--print-fps` is a one-second average, not P95; build the frame-time
   recorder from QA138 refinement item 2 before claiming P95.
7. **Accessibility stays intact.** Reduce Flashes and Reduce Camera Motion apply to every new effect; recovery stays readable without audio
   and without darkness hiding the scene (pillar 3).
8. **Assets:** nothing third-party (model, texture, HDRI, font, sound, shader from a store) without the owner's approval and a recorded
   creator/source/licence/version. Original sources go in `art_source/` (Git LFS); exported assets never contain placeholders at release.
9. **One task per session and branch** (CLAUDE.md section 6). Name lookdev work `DS03-...` or `A01-...` as the backlog/workstream says. Evidence in
   `docs/evidence/<ID>.md` with what was not verified.

## 6. Owner decisions on section 4 (9 Nov 2026)

Recorded in the design session of 9 Nov 2026 (branch `task/DS07-design-mandate-plan`). The owner's words, given when hiring Claude as the main
design artist and developer: the current design and graphics are "extremely poor"; "make the game better looking, intuitively understandable,
easy to play and navigate; more levels and tasks"; "design and playability and UX and intuitive understandability should be prioritized and
finished"; "perform the most beneficial way"; "make it the best".

1. **Decision 4.1, lookdev spike before V09: APPROVED, 9 Nov 2026.** The owner's mandate above is the yes. The spike scene
   `scenes/lookdev/alder_lookdev.tscn` may fake supply states (labelled). ADR-017 decision 2 adds when the reusable look (which never fakes
   state) may also dress the mission scene.
2. **Decision 4.2, renderer: KEEP COMPATIBILITY, 9 Nov 2026.** Owner's answer to the question with the QA140 numbers (GTX 1650 1080p P95 about
   4 ms, Vega 10 about 3.3 ms, Intel UHD 7.8 ms at 2560x1600; Mobile similar frame time but about 2x memory and longer load stalls;
   Forward+ about 2x slower on integrated GPUs): "Keep Compatibility". The locked decision stands. The lookdev is designed for Compatibility
   only (no SSR, SSAO, SDFGI or volumetric fog) and is measured with the QA140 harness; the dual-renderer A/B in 4.2 is dropped.
3. **Decision 4.3, art capacity: CLAUDE IS THE DESIGNER, 9 Nov 2026.** The owner's answer: "I hire you as a designer, make necessary
   instructions and have our design agent ready to work as soon as it is necessary. You can build lighting, materials, VFX and kit props now.
   After you approve the lookdev look, start the design agent for solid professional design and necessary elements design."
   - Claude builds lighting, materials, VFX and kit props now, project-made only.
   - **Claude (lead designer) approves the lookdev look**, against ADR-004 and the DS07 plan, with the three-state screenshots as the record.
   - Then the project design agent (`.claude/agents/lbo-design-artist.md`) is started for the element design listed in
     `docs/design/DS07-design-plan.md`.
   - Unchanged: any third-party model, texture, font, sound or shader still needs the owner's approval and a recorded creator, source, licence
     and version before import (ADR-004 point 6, CLAUDE.md section 6). Spending money (for example commissioning a human artist) is still
     the owner's call.
