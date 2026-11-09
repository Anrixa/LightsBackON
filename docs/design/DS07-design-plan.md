# DS07: Design plan for C01 and the content path ("Stormglass / Civic Revival")

- Author: Claude, main design artist and developer (owner mandate, 9 Nov 2026; ADR-016 section 6, ADR-017).
- Date: 9 Nov 2026. Baseline: `main` 33b2c48 (after QA140).
- Based on what is on screen: `capture_district_views.gd`, `capture_hud.gd` and the C01 mission scene at spawn, rendered on the owner's PC
  (RTX 5090, Compatibility renderer, 1920x1080) on 9 Nov 2026. Before-images: `docs/evidence/img/DS07_before_*.png`.
- Binding rules this plan follows: CLAUDE.md (pillars, power rules, authority), ADR-004 (tokens, icon + text, AA contrast, licensing),
  ADR-016/017 (Compatibility renderer, state honesty, lookdev gate open), the blueprint pages on UI/art/audio (p.11-12) and contracts (p.18-21).

## 1. Diagnosis: what a new player sees in the first minute

Ranked by how much each one hurts a first-time player. W = world, U = UX.

| # | Problem on screen | Why it matters |
|---|---|---|
| W1 | Every surface is the same flat blue-grey; one colour sky, flat ambient, no rain, no shadows that read. | Nothing says "storm night in a neighbourhood". Restored windows do not stand out because the scene is lit like an overcast noon. Pillar 3 has no stage. |
| W2 | Debug IDs float above buildings as billboards: `APT_W`, `JW`, a giant `VAN`, with `[-] NO POWER` under them. | Reads like an editor, not a game. IDs mean nothing to a player. |
| W3 | All buildings are the same box in the same colour. | No landmarks: a player cannot say "the pub" or "the green market" and cannot navigate by memory. |
| W4 | Junction cabinets are plain blue boxes; the van is a white box. | The two most important objects of the first minute (van = home base, cabinet = first repair) are unreadable. The power network is invisible in the world. |
| U1 | First hint: "Move around the van and look for dark service buildings." | Every building looks equally dark, so the hint gives no direction. The first useful action (meter on the west junction) is not discoverable. |
| U2 | Three objectives, all with the same "active" icon. | The player is not told what to do *now*. |
| U3 | Crew panel says `You (You)` in solo. | Looks like a bug. |
| U4 | Tool bar shows 4 of 5 tools plus "+1 more"; the cable reel is hidden. | An essential tool (generator cable) is hidden at the start. |
| U5 | Tablet opens with the five required consumers clipped below the fold (QA138 item 4). | Pillar 1 evidence needs panning to find. |
| U6 | `unknown` token measures 4.59:1 (x1.02 of AA) on the tablet panel (QA138 item 5). | Passes, with no headroom. |
| U7 | 200-700 ms frozen frame between menu and mission (QA140 finding 4). | Feels like a hang. |
| U8 | Binding prompts are bracketed text (`[E]`, `[MMB]`). | Readable, but not the industry convention of key/button glyphs (ADR-004 point 3). |

The UI itself (tokens, icons, contrast, reflow, focus) is sound and tested; it is the world and the first-minute flow that fail.

## 2. Design principles for every phase

1. **Every pixel of status comes from the host.** Glow, signs, lamps and sounds read host snapshots (`RestorationPresentation`). Fake
   states only in `scenes/lookdev/`, labelled "FAKE STATE" in every caption.
2. **Pillar 1, evidence not answers.** The world shows symptoms (dark windows, a silent building, a cabinet with a closed door). Diagnosis
   needs the meter and the tablet. No world cue names the failed part.
3. **Pillar 2, the tradeoff is visible before it bites.** Generator load is shown where the player stands (on the generator), with
   capacity and current load, before the 1.5 s trip.
4. **Pillar 3, recovery is the reward.** Dark state is cool, readable and calm; temporary is cool white and "borrowed"; restored is warm,
   inviting and loud. The three states differ in hue, brightness, sound and sign text, never in hue alone.
5. **Landmarks over markers.** Each building gets a distinct silhouette accent, palette and sign so players navigate by name and look.
6. **Compatibility renderer, measured.** Fog, glow, tonemapping, directional shadows, emissive surfaces, a few unshadowed lights, CPU/GPU
   particles. No SSR, SSAO, SDFGI or volumetrics. Every look change is measured with the QA140 harness.
7. **Accessibility is part of the look.** Reduce Flashes and Reduce Camera Motion cover every effect; icon + text for every status;
   224/224 rendered HUD contrast after every lighting change.

## 3. The look: "Stormglass" lighting recipe

One reusable look (`scripts/world/street_look.gd`, data in `content/world/look_stormglass.json`) used by the lookdev scene and the mission.

| Layer | Recipe (Compatibility) | Reads as |
|---|---|---|
| Sky | Project-made sky shader: deep storm blue zenith, lighter blue-grey horizon band, slow cloud noise, a faint warm glow on one horizon (a powered district far away). | Blue-hour storm, with a hint that power exists elsewhere. |
| Key light | Cool moonlight directional light, low energy, shadows on (PSSM 2 splits, short distance). | Shape and depth on the kit without a "noon" look. |
| Fill | Ambient from the sky colour at moderate energy, so dark buildings stay readable (pillar 3, ADR-004 point 1). | Night, but never hiding content. |
| Fog | Depth fog in the horizon colour, light density; hides the envelope edge and the far boundary. | Rain-filled air, depth. |
| Tonemap + glow | Filmic/ACES-style tonemap, glow on emissive only (high HDR threshold), so windows and lamps bloom and the street does not. | Warm windows "pop". |
| Wet ground | Asphalt and paving materials with low roughness and darker albedo; lamp and window light make long specular streaks. Kerbs, lane marks, drains as thin meshes. | Rain-soaked street without SSR. |
| Rain | Camera-following particle volume of thin streaks, plus slow drifting mist. Density scales down with Reduce Flashes (no lightning flashes at all in v1). | Storm identity. |
| Street lamps | A few cool-white municipal lamps on their own feed (the substation is online in C01: GRID is 24 PU). | Navigation light and the cool half of the warm/cool contrast. |
| Windows | Dark: deep blue glass that catches the sky. Temporary: cool white-blue, lower energy, with the generator's colour. Restored: warm cream (`#FFD180`) with glow and a light spill on the pavement. | The three supply states at a glance, plus the sign text. |
| Van | Work lights (amber beacon, white rear flood) always on: it is the crew's own power. | Home base, readable from anywhere. |

Per-building palettes (project-made shader parameters, no textures needed): West apartments red-brown brick, corner market teal shopfront,
pub deep green with a gold fascia, east apartments cream render, workshop corrugated grey-blue, pump house raw concrete with hazard yellow.

## 4. Phases (one branch, PR and evidence file each)

Each phase ships tests, `docs/evidence/<ID>.md`, a 1920x1080 three-state screenshot set in `docs/evidence/img/`, rendered HUD contrast
224/224, and is merged after the `linux` and `windows` CI jobs pass. P95 frame time is measured for every phase that changes the 3D scene.

### DS08: Stormglass look and diegetic world (this session)
- `StreetLook`: sky, moonlight, fog, tonemap, glow, wet materials, per-building palettes, rain, street lamps (section 3).
- `StreetDressing`: project-made props from primitives on the 4 m kit grid: work van with lights, utility cabinets with stencilled
  junction plates, street lamps, kerbs, lane marks, drains, bollards, a substation enclosure where the grid feed enters, overhead feeder
  lines on poles from the substation to the two junction cabinets (the network becomes visible in the world), a distant skyline with a few
  lit windows beyond the boundary.
- **Diegetic signs replace the debug-ID billboards.** Building name boards on the facade from localization keys ("Alder Apartments West",
  "Corner Market", "The Lantern pub", "Alder Apartments East", "Workshop", "Pump House"), each with a status plaque: supply icon + text
  driven by the host snapshot (keeps the colour-blind support of DS04). Junction cabinets get stencilled plates ("West junction JW").
  The giant `VAN` label goes; the van is recognisable on its own.
- Lookdev scene `scenes/lookdev/alder_lookdev.tscn` with labelled fake states for the three-state screenshots; capture tool
  `tools/godot/capture_lookdev.gd`.
- Mission uses the same look (ADR-017 decision 2) after the contrast and P95 checks pass.

### DS09: First-minute clarity (next session)
- Onboarding copy names the first target: "Your first job is the west junction cabinet beside the street. Equip the meter (1) and inspect
  it." The first-step hint points at the cabinet by its new name and plate; no marker reveals the repair (pillar 1).
- Objective card: one row is "Now" (highlighted, active icon), the rest are "Later" (pending icon). The model already has
  STATUS_ACTIVE/PENDING; the presenter decides which active row leads from the mission director's order.
- Crew row: "You" once (fix the `You (You)` duplication); solo hides the empty crew panel rows.
- Tool bar shows all five tools at 100 % UI scale on 1920x1080 (compact icons + numbers when needed); "+1 more" never hides an essential tool.
- Tablet: default zoom fits the whole network when body text stays at least the body size (QA138 item 4).
- `unknown` token to at least 5:1 on the panel (ADR-004 token change by the lead designer under the delegation, recorded in an ADR-004
  addendum; QA138 item 5).
- Loading screen with the shift briefing and a shader/material warm-up pass so the first mission frame does not stall (QA140 finding 4).
- Measure: a scripted first-minute walkthrough (time to first meter reading) on the exported build, recorded as a target to test with people.

### DS10: Fault evidence in the world (pillar 1)
- Cabinet states drawn from repair states: door closed/open, isolation handle position, fuse carrier visible when opened, a cut trunk end
  hanging when the trunk is broken and the panel is opened. All from host repair state, never ahead of it.
- The meter tool shows the reading on its own display in first person (the HUD keeps the text version).
- Tablet and world agree: pinging a node on the tablet shows the ping on the real cabinet (comms already exist, V06).

### DS11: Temporary supply tradeoff (pillar 2)
- Generator prop with a physical load gauge (`x / 6 PU`) and a warning state while overloaded; the 1.5 s trip shows as a filling ring on
  the gauge and the HUD, with a distinct sound, before the breaker drops.
- Cable as an authored curve between socket and pad (CLAUDE.md: never rigid bodies); pads painted on the ground.
- Pub alternate route: the "never both" rule is shown by the switch plate, and the refusal highlights the conflicting tie (already in the
  tablet).

### DS12: Recovery payoff (pillar 3)
- Restoration cascade: windows, then shop signs (neon tubes in the building colour), fans and extractor sounds, street-level light spill.
- Audio: project-made procedural ambience (rain bed, distant thunder rumble without flashes, generator hum, building hum on restore) and a
  short restore stinger; music layer opens up as services return. Any third-party sound needs the owner first.
- Results screen shows the restored street (camera move off when Reduce Camera Motion is on).

### DS13: Input glyphs and prompts
- Project-drawn keyboard/mouse and controller glyph set in the ADR-004 icon family; prompts switch with the last device used and follow
  remapping. Replaces bracketed text labels.

### DS14: Hands, tools and hero props (design agent)
- First-person gloved hands and the five tools, the generator, cable reel and the worker rig variants, made by the design agent from
  project code (procedural meshes and shaders) to the DS08 look; a human artist only if the owner decides to spend money.

### Content track (parallel, logic only; ADR-017 decision 3)
- **CT-L1: C02-C04 (Alder Street, same kit).** C02 Dinner Rush (two faults, opening-time optional deadline), C03 Roof Route (bypass feeder,
  ladder latch), C04 The Whole Block (direct sign spur). Each: grid, mission, repairs, equipment, switches and tablet data under
  `content/contracts/cNN_*`, a solution trace replayed by `tools/godot/validate_solution.gd`, a wrong-route test and a missed-optional test.
- **CT-L2: C05-C08 (Canal Yard baseline)** and **CT-L3: C09-C12 (Hill Road baseline)**, same checklist. Their districts are graybox until
  CT01/CT02 art, which follows the approved C01 look.
- Every contract ships with a solution trace that the validator replays (CLAUDE.md section 3). Timers and optional deadlines are targets
  to playtest, not facts.

## 5. Order and why

1. DS08 first: the owner judges by the screen, and every later phase (signs, cabinets, generator, payoff) needs the look to be designed in.
2. DS09 next: the cheapest large gain in "intuitively understandable".
3. DS10-DS12 in pillar order; each makes the core loop more legible.
4. DS13-DS14 when the look is approved and the design agent starts (ADR-016 section 6.3).
5. Content runs in parallel as logic and data, so C02-C12 are ready to dress when their districts get art.

## 6. What this plan does not decide

- Anything network-related (F02/F06 remain the biggest risk).
- Third-party assets, money, the public game name.
- Gameplay numbers: timers and capacities stay design choices until measured with people.
