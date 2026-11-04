# DS01 — Evidence-backed comparable-game benchmark
Snapshot: 2026-11-05. Scope: public store listings and visual/UI conventions, **not** hands-on gameplay or a 1,000-game audit.

## Identification and honesty
Lights Back On is a first-person, solo/1–4 player electrical-fault puzzle and neighborhood restoration game. Its closest useful comparisons are task-feedback/repair sims plus environment-restoration and communication games. No single game below exactly matches its genre. Public Steam review counts are **reception/adoption proxies only**, not verified unit sales, profitability, conversion or Steam rank. Counts and percentages change; figures are source snapshots only.

**Verified titles in this first tranche: 7.** The user's proposed upper bound of 1,000 refers to a future screened candidate set; no 1,000-title study was done. For each row the analyst checked the linked public Steam page (except supplemental Unrailed ratings as noted), inspected the described gameplay/UI, and derived a transferable *hypothesis* rather than reporting a validated design effect.

| Game and source | Public review evidence checked (approx. Nov 2026) | Genre proximity | Relevant design pattern | Do **not** copy |
|---|---|---|---|---|
| [PowerWash Simulator](https://store.steampowered.com/app/1290000/) | ~51,100 Steam-purchaser reviews across languages, overwhelmingly positive; current Steam English score 97% in ~38.6k reviews | First-person job / cooperative restoration loop | Immediately visible incremental transformation, tool-centered first-person feedback, minimal task UI | Branded color/shapes, specific sounds or UI |
| [House Flipper 2](https://store.steampowered.com/app/1190970/) | ~16,900 Steam-purchaser reviews, very positive | First-person restoration; 2–4 player co-op | Inviting interiors, approachable tool affordances, inviting before/after comparisons | House/room designs, menus or branded assets |
| [Hardspace: Shipbreaker](https://store.steampowered.com/app/1161580/) | ~19,500 Steam-purchaser reviews, very positive | First-person technical diagnosis and work | Tool identity; contextual actionable status without unnecessary simulation detail | LYNX corporate treatment, instruments or interface |
| [Loddlenaut](https://store.steampowered.com/app/1644940/) | ~3,850 Steam-purchaser reviews, overwhelmingly positive | Environment repair, single-player (not co-op) | Positive environmental response and strong silhouette/color grouping | Characters, aquatic art, neon palette |
| [Car Mechanic Simulator 2021](https://store.steampowered.com/app/1190000/) | ~37,400 Steam-purchaser reviews, overwhelmingly positive | Tools and repair workflow, single-player | Meaningful action staging and object-readable component layout | Cars and repair animations |
| [PlateUp!](https://store.steampowered.com/app/1599600/) | ~19,100 Steam-purchaser reviews, very positive | Cooperative task allocation (not first-person) | Shared task ownership and concise information hierarchy | Restaurant or card UI artwork |
| [Unrailed!](https://store.steampowered.com/app/1016920/) | Independently reported ~19,700 reviews and 93% positive in Aug 2026 ([dated snapshot](https://friendslop-games.com/games/unrailed)) | 1–4 player cooperation and resource tradeoffs | Players can infer others' activities from spatial state and simple task language | Voxel characters, tracks, progression systems |

## Candidate design identity — "Stormglass / Civic Revival"
Not a rebrand or change of locked design: **recognizable maintenance work in a blue-hour rainstorm, followed by a warm neighborhood returning to life**.

1. **Dual emotional palette:** cool slate/blue outdoor fill and wet dark asphalt, warmly lit cream windows and storefronts on the *restored* branch only. Preserve ADR-004 UI tokens, compatibility renderer and 4 m kit. Do not replace the UI with a light theme.
2. **State honesty:** dark, temporary generator and fully grid-powered must be visibly distinct through color *and* shape/text. The host power-grid state remains authoritative; never make an unpowered service glow to make a screenshot attractive.
3. **Tactile diagnosis:** focus framing on real meter/cabinet/tool states. Lens/reticle and labels identify interactable objects, not the exact hidden fault answer.
4. **The moment of restoration:** stage safe transitions window-by-window and with nonflash ambient responses, short audio, and the objective chip. Reduce Flashes is respected; no essential state is communicated by a strobe.
5. **Readable cooperation:** crew role/task chips, pings, equipment footprints and map states emphasize actual work, not noisy fake telemetry. Keep a voice-free completion path.
6. **Original authored quality:** simple grounded proportions, reflectors, brushed repair hardware and clear gloved-hand silhouette; do not trace or reproduce reference assets.

## Evidence-based priorities
- P0 design-system invariants: 4.5:1 text / 3:1 large/icon contrast (rendered over actual scene); distinct status icon plus label; correct state; 48 px target at design scale; 80 px safe area; 80–150% UI reflow; no content leaks; no flashing or camera-motion surprises.
- P1 first impression: menu action focus, scrollability on small windows, readable first objective/prompt, safe default accessibility.
- P1 feedback: restored windows and audible cue derived from state, not from player command request; document reduced-flash alternative.
- P2 production: polished authored district geometry, weather, iconography, tool/worker rig, environmental audio, tonal transition, clean capture pipeline.
- Nonclaims: source review numbers cannot measure completion pleasure, conversion or retention. No full competitive usability study or user testing was conducted. Screenshots still require owner GPU inspection.

## Next research tranche (DS02)
Define inclusion pool (published on PC, meaningful mechanic overlap, primary storefront sources, identifiable review snapshot); screen up to 1,000 metadata candidates **only if source collection is reliable**; deep-score 20–30 relevant titles (not every screened title). Record source IDs, timestamps, disqualifications, a 0–4 rubric for task legibility, state transformation, tool identity, co-op cues, accessibility and performance constraints. Report *actual* screened/deep-scored counts and confidence for every observation. Do not infer revenue from reviews.

## Boundaries
Source-only research; no competitor art, screenshot, fonts, audio, models, SDKs or UI code added to the game. ADR-004, V09 art gate, F02 Steam block and local hardware UX01 remain binding.
