# Lights Back On — EXP012–EXP021 / Original blueprint reconciliation

**Source:** protected `main` at `a1cffca9fd3efe619b0cc82f92c9d9202f8bbd1b` on 2026-11-23. This report is an **acceptance-evidence audit**, not a product-approval certificate. The historical `docs/backlog.json` and all 66 original statuses are preserved.

## Three different percentages (do not average them)

| Dimension | Measured numerator / denominator | Coverage | Interpretation |
| --- | ---: | ---: | --- |
| **Game engineering implementation evidence** (pre-beta blueprint F/G/V/A/D/CT/H) | **40/54** | **74.1%** | At least some relevant code/source/test evidence. A partial overlap counts as *touched*, not finished, and does **not** certify a playable game. |
| **Playable alpha evidence gates** | **6/16** | **37.5%** | Exact count of qualified source/host/build prerequisites. Physical playability and alpha sign-off are **HOLD**. |
| **Commercial release evidence gates** | **2/12** | **16.7%** | CI/build-integrity prerequisites only. Steam, beta, store approval and final release remain **HOLD**. |

These are **transparent, unweighted gate/coverage ratios, not measured percent of labor, subjective game quality, or a single defensible estimate of remaining development time**. In particular, commercial approval is binary and remains **not achieved**.

## Original 66-task accounting

| Original status | Number | Percent |
| --- | ---: | ---: |
| DONE / fully accepted | 5 | 7.6% |
| CLOUD_VERIFIED / physically pending | 15 | 22.7% |
| NOT_STARTED (original, unchanged) | 45 | 68.2% |
| BLOCKED | 1 | 1.5% |

**Reconciled evidence overlay:** 5 accepted + 15 cloud verified + 21 additional source overlaps + 1 blocked + 24 without credited implementation proof = 66. Do not promote the 21 overlaps to DONE or CLOUD_VERIFIED without satisfying the **original** acceptance criteria.

**Pre-beta milestone breakdown:**

| Blueprint stage | Original tasks | Accepted | Cloud verified | Added source overlap | Unqualified/blocked |
| --- | ---: | ---: | ---: | ---: | ---: |
| F | 6 | 2 | 2 | 0 | 2 |
| G | 8 | 3 | 4 | 0 | 1 |
| V | 9 | 0 | 8 | 0 | 1 |
| A | 7 | 0 | 1 | 3 | 3 |
| D | 8 | 0 | 0 | 5 | 3 |
| CT | 10 | 0 | 0 | 8 | 2 |
| H | 6 | 0 | 0 | 4 | 2 |

## Why the new work matters — without overstating it

- **Source authored:** 25 regions, 200 location/level identities, 1,000 task IDs, 25 region narratives, 200 work orders, host-validated tools, host/evidence/reward continuity and 200 source-bound scenes. See `docs/evidence/EXP019-A01.md`, `EXP019-A02.md`, `EXP020-A01.md`–`A05.md`, `EXP021-A01.md`–`A05.md`.
- **Observed integrated Godot regression:** main [CI run #45104016469](https://github.com/Anrixa/LightsBackON/actions/runs/45104016469) has Linux and Windows SUCCESS, **1,068 tests, 0 failed, 497,600 assertions on each platform**, 200 scenes/hosts, 1,000 task bindings, and **7,200 real physics-ray contacts**. Windows exact-head EXE/PCK/source-digest preflight passed. This is strong code qualification, not gameplay certification.
- **Original 12 contracts:** host/source solutions and deterministic authoring have CI-backed coverage, but this is not a person completing all 12 contracts in the shipping 3D world. The original C01–C12 identifiers, saves and economics remain protected.
- **Physical GPU nuance:** `docs/evidence/QA140.md` records real GTX 1650, Vega 10 and Intel UHD measurements for an **older C01 graybox**. It explicitly states those runs satisfy no current gate. Do **not** describe the project as having no historical GPU data, and do **not** transfer those frame times to EXP021.
- **Important defect debt:** Latest full-run success still logged a deliberately rejected UI intent as `ERROR`, **572 CanvasItem RID leaks**, **1,445 ObjectDB instances at exit**, plus shaped-text/font RID leak output. Resource cleanliness is not certified; focused 11-test EXP021 gate was much cleaner, but it does not erase the full-suite diagnostics.
- **200/200 source scenes is not 200/200 completed playable missions.** Full MissionDirector completion, real people/controllers, two genuine Steam clients, full campaign saves/rewards, human content diversity approval, current hardware frame profiles, store approval and release remain HOLD.

## Evidence-gated alpha checklist

| Gate | Result | Requirement |
| --- | --- | --- |
| AL01 | PASS | Immutable contract/atlas source identities |
| AL02 | PASS | Original C01–C12 headless source/host solutions |
| AL03 | PASS | 200 live Godot scene and host constructions; 1000 task bindings |
| AL04 | PASS | Host-authoritative field tools, dedup and evidence/repair checks |
| AL05 | PASS | 200 source-physics worksites and 7200 registered ray contacts |
| AL06 | PASS | Exact-head Windows EXE/PCK manifest, boot and hash proof |
| AL07 | HOLD | 200 full MissionDirector completions with source-bound solutions |
| AL08 | HOLD | Human walking and collision/access audit across representative final worksites |
| AL09 | HOLD | Keyboard/controller complete real-world campaign navigation and accessibility |
| AL10 | HOLD | Current integrated 200-site exported-build target GPU P95/VRAM/memory |
| AL11 | HOLD | EXP campaign save recovery, migration, reward dedup, process restart on hardware |
| AL12 | HOLD | Two-real-network Steam transport plus four-player authoritative sessions |
| AL13 | HOLD | Visual/audio quality and reduced-flash behavior on real hardware |
| AL14 | HOLD | Human-tested UI focus, 150 percent scale, language and non-audio cues |
| AL15 | HOLD | Independent game playthroughs, metrics and P0/P1 disposition |
| AL16 | HOLD | Lifecycle and resource-leak closure in full Godot regressions |

## Commercial release checklist

| Gate | Result | Requirement |
| --- | --- | --- |
| RL01 | PASS | Main branch full CI passed on Linux and Windows |
| RL02 | PASS | Windows exact-head EXE/PCK source and digest qualification |
| RL03 | HOLD | Signed-off physically playable feature-complete alpha gate |
| RL04 | HOLD | Steam real-peer, Steam Cloud, achievements and account isolation |
| RL05 | HOLD | Multi-network/device/impairment four-player beta matrix |
| RL06 | HOLD | Controller/accessibility/localization beta acceptance |
| RL07 | HOLD | Final-target representative hardware P95, endurance and leak closure |
| RL08 | HOLD | Approved final art/audio, store screenshots/trailer, license audit |
| RL09 | HOLD | Steam release app/depot package, storefront configuration and review |
| RL10 | HOLD | Valve store/build review approvals documented |
| RL11 | HOLD | Exact production Steam download clean install and final smoke |
| RL12 | HOLD | Release sign-off, rollback candidate, support and publishing operations |

## Reconciled 66 original tasks

Classification is an overlay. **No prior statuses have been rewritten.** Evidence file paths and the precise remaining original acceptance limitation for each entry are stored in [roadmap-reconciliation.json](./roadmap-reconciliation.json). The table below is the human-facing index.

| Task | Original status | Reconciled evidence | Source reference / main gap |
| --- | --- | --- | --- |
| F01 | DONE | ACCEPTED | `docs/evidence/F01.md`; Original backlog acceptance met. |
| F02 | BLOCKED | BLOCKED | none; No second Steam account yet; GodotSteam and app 480 not approved. Owner deferred F02 on 29 Oct 2026 (ADR-011); resume at PC-RUNBOOK session D. |
| F03 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/F03.md`; rerun the F03 tests on the qualified Steam peer (F02 tuple) between two PCs on separate networks; NET01/NET02 with two real clients |
| F04 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/F04.md`; Steam-offline start of the exported build (REL02); real host shutdown (NET07) and same-participant reconnect (NET06) on the Steam peer |
| F05 | DONE | ACCEPTED | `docs/evidence/F05.md`; Original backlog acceptance met. |
| F06 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| G01 | DONE | ACCEPTED | `docs/evidence/G01.md`; Original backlog acceptance met. |
| G02 | DONE | ACCEPTED | `docs/evidence/G02.md`; Original backlog acceptance met. |
| G03 | DONE | ACCEPTED | `docs/evidence/G03.md`; Original backlog acceptance met. |
| G04 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/G04.md`; NET01 with two real clients and range from real movement (G07); prompt/selection against real scene geometry (V01/V07) |
| G05 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/G05.md`; cable visuals and placement against real anchors in the graybox (V01); carrier disconnect with real clients (G07) |
| G06 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/G06.md`; dependency G04 is CLOUD_VERIFIED (G06 writer acceptance itself passed: 200/200 real-process kills of the exported Windows build, docs/evidence/G06.md); ver |
| G07 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/G07.md`; two real peers (F06 tuple) agree by state hash after repair, trip, reset and reconnect; G08 gate |
| G08 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| V01 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/V01.md`; UX01: a person walks every route with a controller once a player controller scene exists (automated CharacterBody3D walk passes); G08 grid toy gate still n |
| V02 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/V02.md`; known-solution playthrough in the V01 graybox with real positions and reach; C01 pacing targets with people; objective HUD rendering (V07) |
| V03 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/V03.md`; out-of-bounds detection and van-menu recovery in the V01 graybox; guest disconnect while carrying over real peers (NET05) |
| V04 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/V04.md`; real remote join during pump/repair and reconnect on the F02 Steam tuple between two networks (NET04, NET06); joining screen UI |
| V05 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/V05.md`; controlled impairment on real peers (NET09) on the F02 Steam tuple; collision in the V01 graybox; feel test with people |
| V06 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/V06.md`; two testers complete C01 with voice disabled using pings alone (human, graybox, two clients); comms UI and radial menu (V07) |
| V07 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/V07.md`; UX01: a person runs the live HUD, network tablet, pause/accessibility and scroll controls with a physical controller; measure focus/pan/zoom/evidence scrol |
| V08 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/V08.md`; receipts delivered over real peers on the F02 tuple; results screen UI; Steam Cloud sync of profile and receipts (H05) |
| V09 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| A01 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/DS08.md`; Final C01 benchmark street and three approved hardware-readable restoration states not accepted. |
| A02 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/DS12.md`; Integrated hardware audio balance, accessibility and restoration presentation remain untested. |
| A03 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/A03-MEASURE01-MEASURE20.md`; Opt-in measurement producer exists; original A03 remains NOT_STARTED pending V09 and observed consented sessions. |
| A04 | CLOUD_VERIFIED | CLOUD_VERIFIED | `docs/evidence/A04.md`; Repeat live camera bob suppression and monotone reduced-flash restoration on physical Windows GPU; confirm status remains legible during power recovery and |
| A05 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| A06 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| A07 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| D01 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/DS14.md`; Partial first-person props and procedural art do not establish final C01 facade and tool readability certification. |
| D02 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/V07.md`; Menu and solo-flow portions exist; all 12 UI screen groups and real lobby loops not acceptance-tested. |
| D03 | NOT_STARTED | SOURCE_OVERLAP | `content/ui/strings/en.json`; English string resources exist; Chinese locale, pseudo-locale, long-string tests and language approval remain. |
| D04 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/DS13.md`; Input glyphs and source focus exist; complete mouse-free controller run and remap/conflict checks not witnessed. |
| D05 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/QA140.md`; Real hardware numbers are from an older C01 graybox; EXP021 batching/stress is headless, not latest-release physical P95. |
| D06 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| D07 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| D08 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| CT01 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/CT-BP-GATE.md`; Canal Yard contract source and generic 3D worksite physics exist; bespoke final Canal Yard kit and human route approval absent. |
| CT02 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/CTL3-SOURCE-CLOSEOUT.md`; Hill Road contract source and generic 3D worksite physics exist; final hill/roof kit and controller navigation unapproved. |
| CT03 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/CTL1-C02.md`; C02–C04 host/source solution evidence does not certify fully built player-controlled 3D missions. |
| CT04 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/CTL2-C05.md`; C05–C06 source logic is qualified, but physical pumps, timed paths and solo/online runs remain. |
| CT05 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/CTL2-C07.md`; C07–C08 source and simulated host proofs exist; actual physical evidence-driven missions not signed off. |
| CT06 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/CTL3-SOURCE-CLOSEOUT.md`; C09–C12 source replays exist; four complete player-controlled solo/online final-district contracts not certified. |
| CT07 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/EXP05.md`; EXP05 expedition routing and EXP04 field points exist, but they are separate from original campaign credit purchases and five starter sidegrades. |
| CT08 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/DS14.md`; Source first-person tools and synthetic audio exist; final integrated animation/asset license/full campaign polish missing. |
| CT09 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| CT10 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| H01 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/G06.md`; Cloud-verified checkpoint/restart code exists; old/new version and physical process migration matrix not completed. |
| H02 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/V08.md`; Ledger-backed deduplication is source-tested; cross-client redelivery and production account recovery need live evidence. |
| H03 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/A04.md`; Core UI scaling and reduced-flash source exist; all screens/locales/controller/human accessibility unresolved. |
| H04 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/QA140.md`; QA140 physical runs were C01 graybox only; 200-site exported integrated GPU P95/VRAM, 4-player stress and leak cleanup remain. |
| H05 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| H06 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| B01 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| B02 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| B03 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| B04 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| B05 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| B06 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| R01 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| R02 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| R03 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| R04 | NOT_STARTED | SOURCE_OVERLAP | `docs/evidence/QA57.md`; CI verifies exact-head Windows export and hashes; no tagged clean production build, secret scan, rollback or Steam release candidate. |
| R05 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |
| R06 | NOT_STARTED | NO_ACCEPTED_EVIDENCE | none; Original acceptance criteria not met; inspect dependencies before promotion. |

## Next execution sequence (ordered by dependency, not number of PRs)

1. **Proof before feature sprawl:** Run full individual source-bound mission completion through the real Godot host/MissionDirector for all 200 missions, with wrong/unsafe inputs, repeat/reconnect, and unchanged receipts. Report exact acceptance denominators, elapsed host ticks and failure evidence. Never equate existing scene startups with completions.
2. **Resource lifetime repair:** Reproduce the full-suite 572 CanvasItem and 1,445 ObjectDB exit leaks, distinguish intentional test fixture lifetimes from actual production leaks, fix proven causes, and rerun Linux + Windows CI. Preserve host/saves/rewards.
3. **Physical integrated gameplay and performance:** Export exact integrated main, test C01 and a stratified representative sample across 25 regions on real keyboard/controller and GTX 1650/Vega/Intel GPUs. Record hardware/driver/build hash, frame P95/P99, VRAM/RAM, navigation and actual sound mix. Do not reuse QA140 graybox figures.
4. **Steam F02 blocker:** Qualify the selected GodotSteam/Steam peer with two licensed accounts on different real networks, then four-player source/recovery/authority stress. Do not simulate away acceptance.
5. **Player-facing alpha:** Finish actual 12-contract and expanded-campaign physical solves, save migration/restart and deduplicated reward evidence, UX/accessibility/localization proof, external player studies; record and resolve P0/P1 blockers before an alpha sign-off.
6. **Commercial gates:** Finish late art/licensing, demo and Steam creative, Cloud/achievements, broad network/controller beta, genuine Steam install and Valve reviews, tagged reproducible release and owner publication sign-off.

## Policy and provenance

- This report is additive. It does **not** edit `docs/backlog.json`, the original contracts, any shipped save, runtime scripts, reward ledgers or Git tags.
- `tools/roadmap_reconciliation.py` validates the full 66-row mapping against the original backlog, named evidence paths, and these reproducible scorecards.
- The automatic percent of any evidence checklist **must not** be described as amount of human effort or production readiness.
- Audit revision reflects exactly the verified 23 November 2026 `main` Git tree; later work requires a new evidence review and refreshed gate conclusions.
