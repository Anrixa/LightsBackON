# DS02 — Comparative benchmark, sourced 28-title design relevance study

Snapshot: **2026-11-05 UTC**. Primary source: publicly accessible Steam store product listings linked for each title below; no Steam login, download, game launch, or copied assets. The original [DS01 seven-title baseline](benchmark-2026-11-05.md) was carried forward and extended to **28 unique Steam app IDs**.

## Selection, screening and evidence quality

- **Actual candidate records checked and metadata screened: 28.** **Actual in-depth source-based relevance scores: 28.** A 1,000-title candidate crawl **was not attempted**; it would not be honest to describe 28 known source pages as 1,000 screened titles.
- These are purposively selected comparators: first-person repair and cleaning jobs, environmental restoration, technical/system diagnostics, and cooperative task/puzzle coordination. This is **not** a representative cross-section of the store or a quantified competitive UX experiment. The sample intentionally includes mixed-reception titles as cautionary comparisons.
- Evidence consists of official product descriptions, storefront feature flags, tags and reviews. **No hands-on evaluation, footage frame-by-frame coding, controlled usability study, real-GPU performance profiling, monetization analysis or sales validation was done.**
- Metric: the listed review percentage and count are the precise **English Reviews** or **All Reviews** scope shown on the linked page when checked. These groups are deliberately not combined or treated as a revenue proxy. Storefront counts can change and may differ on revisit.
- Six intended dimensions, 0–4. **T** = task-pattern overlap, **R** = visible-restoration transformation relevance, **I** = tool/interaction identity overlap, **C** = cooperative task signal overlap. 0 = no matching advertised feature, 1 = indirect, 2 = partial, 3 = strong, 4 = direct prominent overlap. These scores measure **documented mechanic relevance to Lights Back On**, **not actual UI quality, commercial success, player experience, retention or accessibility**. Two additional axes — **accessibility quality** and **GTX1650 runtime performance** — are *not observed* for all entries and remain `null` rather than being guessed.
- Scores have **medium** confidence: they are grounded in first-party product descriptions but do not measure what players actually see or perceive. No adverse assessment should be inferred from zero co-op overlap in a store-listed solo title. Numeric scores are an internal prioritization aid, not a scientific scale.
- Selection is bounded to released PC storefront titles with identifiable app ID and stated mechanic. Retailer metadata and app pages were read, rather than executing third-party binaries or calling an undocumented Steam API.

## All sourced titles and scored applicability

¹ Review snapshot: `positive % / displayed review count (scope)`. Counts are not verified units sold. Scores T/R/I/C use only the four applicable axes; the two unassessed axes remain `null` in [the machine-readable source log](DS02-source-sample.json).

| # | Primary-source title | Mechanic family | Review snapshot¹ | T / R / I / C | Source-observed pattern → proposed transfer |
|---:|---|---|---|---|---|
| 1 | [PowerWash Simulator](https://store.steampowered.com/app/1290000/) | restoration | 97% / 38,627 (English) | 4 / 4 / 4 / 3 | Progressively reveal cleaned areas and expose task completion without pinpointing puzzle solutions. |
| 2 | [House Flipper 2](https://store.steampowered.com/app/1190970/) | restoration | 86% / 9,765 (English) | 4 / 4 / 4 / 3 | Stage before/after changes at neighborhood scale; keep tool actions identifiable. |
| 3 | [Hardspace: Shipbreaker](https://store.steampowered.com/app/1161580/) | technical | 89% / 16,352 (English) | 4 / 3 / 4 / 0 | Show a tool's safe work boundary and stage irreversible state changes. |
| 4 | [Loddlenaut](https://store.steampowered.com/app/1644940/) | restoration | 98% / 3,003 (English) | 3 / 4 / 3 / 0 | Give each repaired service an unmistakable environment-level response. |
| 5 | [Car Mechanic Simulator 2021](https://store.steampowered.com/app/1190000/) | technical | 95% / 17,228 (English) | 4 / 3 / 4 / 0 | Separate inspect, diagnose, open and repair affordances in the HUD. |
| 6 | [PlateUp!](https://store.steampowered.com/app/1599600/) | cooperation | 96% / 12,668 (English) | 3 / 2 / 3 / 4 | Expose teammates' station/task ownership in small readable status chips. |
| 7 | [Unrailed!](https://store.steampowered.com/app/1016920/) | cooperation | 94% / 4,687 (English) | 3 / 3 / 3 / 4 | Use location-based pings and equipment silhouettes to convey shared work. |
| 8 | [Electrician Simulator](https://store.steampowered.com/app/1080020/) | technical | 74% / 1,171 (English) | 4 / 3 / 4 / 0 | Make diagnostic observations distinct from repair commands, and signal unsafe preconditions. |
| 9 | [PC Building Simulator](https://store.steampowered.com/app/621060/) | technical | 94% / 19,771 (English) | 4 / 3 / 4 / 0 | Use clearly named components and visible instrument results; avoid false zero readings. |
| 10 | [Train Station Renovation](https://store.steampowered.com/app/914010/) | restoration | 84% / 1,986 (All) | 3 / 4 / 3 / 0 | Use legible site-wide milestone changes rather than only a completion banner. |
| 11 | [The Repair House: Restoration Sim](https://store.steampowered.com/app/1759870/) | technical | 52% / 95 (All) | 4 / 3 / 4 / 0 | Prioritize action sequencing, but treat reception as mixed rather than successful-sales evidence. |
| 12 | [Viscera Cleanup Detail](https://store.steampowered.com/app/246900/) | restoration | 92% / 10,461 (English) | 3 / 4 / 4 / 3 | Make ownership of cleaning tasks and residual work obvious to collaborators. |
| 13 | [Crime Scene Cleaner](https://store.steampowered.com/app/1040200/) | restoration | 98% / 15,814 (English) | 4 / 4 / 4 / 0 | Show per-area progress grounded in actual state, not decorative percentages. |
| 14 | [Gas Station Simulator](https://store.steampowered.com/app/1149620/) | restoration | 87% / 10,704 (English) | 3 / 4 / 3 / 0 | Show the exterior gradually returning to usefulness; avoid scope-heavy economy additions. |
| 15 | [Ship Graveyard Simulator 2](https://store.steampowered.com/app/2201940/) | technical | 75% / 2,005 (English) | 3 / 3 / 4 / 3 | Show tool impact and cooperative shared-object status while keeping repair logic authoritative. |
| 16 | [Workshop Simulator](https://store.steampowered.com/app/1650550/) | technical | 67% / 284 (All) | 4 / 3 / 4 / 0 | Teach a short clear action ladder with immediate object-level feedback. |
| 17 | [Terra Nil](https://store.steampowered.com/app/1593030/) | restoration | 85% / 5,034 (English) | 3 / 4 / 1 / 0 | Use a cool-to-warm neighborhood transformation without imitating the art style. |
| 18 | [The Planet Crafter](https://store.steampowered.com/app/1284190/) | systems | 95% / 38,175 (English) | 3 / 4 / 2 / 3 | Show an intermediate temporary-power state separate from full restoration. |
| 19 | [Satisfactory](https://store.steampowered.com/app/526870/) | systems | 97% / 138,728 (English) | 4 / 3 / 3 / 3 | Provide a compact readable systems map, not overwhelming numerical telemetry. |
| 20 | [Factorio](https://store.steampowered.com/app/427520/) | systems | 98% / 118,802 (English) | 4 / 2 / 2 / 3 | Keep circuit/map consequences causal and distinguish potential from active routes. |
| 21 | [Keep Talking and Nobody Explodes](https://store.steampowered.com/app/341800/) | cooperation | 98% / 8,144 (English) | 4 / 1 / 3 / 4 | Build descriptive nonspoiler evidence and teamwork hints without mandatory voice chat. |
| 22 | [Escape Simulator](https://store.steampowered.com/app/1435790/) | cooperation | 95% / 9,020 (English) | 4 / 2 / 4 / 3 | Keep inspection targets and work-state prompts discoverable with controller input. |
| 23 | [We Were Here Together](https://store.steampowered.com/app/865360/) | cooperation | 82% / 5,027 (English) | 4 / 2 / 2 / 4 | Support useful pings and shared objective language; no voice-only requirement. |
| 24 | [Deep Rock Galactic](https://store.steampowered.com/app/548430/) | cooperation | 97% / 171,609 (English) | 3 / 3 / 4 / 4 | Differentiate roles by equipment shape and concise team status without combat systems. |
| 25 | [Pacific Drive](https://store.steampowered.com/app/1458140/) | technical | 82% / 14,417 (English) | 3 / 3 / 3 / 0 | Use clearly authored storm conditions and tool-readiness cues; avoid driving scope. |
| 26 | [ASTRONEER](https://store.steampowered.com/app/361420/) | systems | 91% / 54,135 (English) | 3 / 4 / 3 / 3 | Make power routing visually traceable through spatial installations. |
| 27 | [Fresh Start Cleaning Simulator](https://store.steampowered.com/app/1856030/) | restoration | 86% / 1,501 (English) | 3 / 4 / 3 / 0 | Provide immediate before/after environmental proof of progress. |
| 28 | [Stationeers](https://store.steampowered.com/app/544550/) | systems | 88% / 5,985 (English) | 4 / 2 / 3 / 3 | Maintain explicit unknown/measured values and reject unsafe topology actions. |

## Source-based comparisons most directly worth carrying forward

- **State transformation / restoration**: PowerWash Simulator, House Flipper 2, Loddlenaut and Fresh Start explicitly put restoration at the center of their advertised loop. For Lights Back On, show light return on the authoritative *restored* branch, not decorative brightenings for a screenshot. It is only a design hypothesis that this increases satisfaction.
- **Diagnosis and staged work**: Electrician Simulator, PC Building Simulator, Car Mechanic Simulator 2021 and Hardspace: Shipbreaker emphasize tools and technical service. Transfer clear measure → isolate → repair → verify stages, with the C01 evidence model and actual safety preconditions.
- **Shared tasks without mandatory speech**: PlateUp!, Unrailed!, Deep Rock Galactic and We Were Here Together illustrate different levels of team coordination. Their store pages cannot prove that text/pings alone suffice: this is a Lights Back On acceptance requirement to test independently.
- **Hazard and weather clarity**: Pacific Drive is a storm-atmosphere reference only. It does not justify adding vehicles, heavy weather physics or combat. Preserve light-source clarity on a GTX1650-class GPU.

## Eight actionable decisions and verification requirements

| Priority | Transfer hypothesis | Exact Lights Back On action | Required independent qualification |
|---|---|---|---|
| P0 | Restoring a neighborhood must be perceptible | DS04 / A02: drive window/service glows from actual host state, show distinct dark / temporary / grid status as icon **and** text | Automated branch states + human rendered before/after screenshots |
| P0 | Technical work needs safe, ordered feedback | Keep the meter evidence / `?` unknown state and the durable repair ladder; add view-only explanatory error copy for rejected isolation | Tests of accepted/rejected commands; human first-repair discovery |
| P0 | Restoration must not rely on flashes | Maintain monotone fades and the persisted Reduce Flashes preference from A04 | Mid-transition toggle and reopening tested; GPU photosensitivity review |
| P1 | The player should identify their active tool at a glance | DS03: improve original first-person tool silhouette and selection framing without copying reference meshes | Owner-approved original art provenance and screen capture |
| P1 | Team tasks benefit from readable ownership | V06/V07/DS05: use existing crew chips and pings for lock ownership, objective and carried supply state | Two real peers and controller-only no-voice task run |
| P1 | A tutorial should help without solving the fault | A04/DS05: keep hints progressive and nonspoiler, label available bindings, never change host results from hints | UX01 blinded first-repair study with 80/100/150% UI |
| P1 | A cooperative grid puzzle needs a simple causal map | Retain solid/dashed edges for measured vs unknown, forbid showing hidden exact cause | Canonical grid/hash tests + rendered tablet 720p/pseudo-locale |
| P2 | Atmosphere should support, not conceal, working status | DS03 after V09: author cool storm ambience vs warm restored panes using original kit | Windows exported GTX1650 P95/memory + rendered contrast and owner review |

**Avoid transferring:** competitor UI layouts, trademarks, screenshots, meshes, colors, fonts, sounds, characters, revenue estimates or unverified accessibility claims. Their artistic design and code are not licensed by these product listings. No external asset/dependency is introduced by DS02.

## What this evidence cannot establish

1. A Steam review count is neither verified sales nor a causal explanation of popularity.
2. Co-op listing does not demonstrate useful iconography, no-voice completion or controller focus.
3. Storefront screenshots cannot establish performance, display brightness, photosensitivity safety or rendered UI contrast.
4. The user-requested potential 1,000-title crawl has **not** been performed; there is no invented 1,000-row dataset.
5. All source URLs may be accessed without a Steam account, but those pages are not Steam transport qualification.

## Next steps after DS02

Proceed to DS04 code-side audit only if its blocked A02 dependency is explicitly treated as preparation, **not** DONE; or complete the first actionable official backlog gate with physical hardware and a person. DS01 screenshot/owner review and DS03/V09 remain pending. Consult the linked GitHub issues for human-only tasks; do not silently change the canonical 66-task backlog.

**Reproducibility:** `python3 tools/validate_ds02.py` and `python3 -m unittest discover -s tests/python -p 'test_*.py'` are part of CI through `tools/run_tests.sh`. The machine-readable log captures source URL, review metric scope, date, observable mechanic, transfer hypothesis, confidence and six-axis scoring for each title.

