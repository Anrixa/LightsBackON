# EXP01 — 200-location dispatch atlas and 1,000-task foundation

> **Superseded (23 Nov 2026):** the owner replaced this scope with 24 designed locations and 960 solver-checked challenges
> (`docs/adr/ADR-019-designed-locations-and-challenges.md`). The dispatch levels are retired in RB01 (hidden) and RB14 (removed).

**Baseline:** main 85f3f6c89fa613bac726b8328d6ec20fe6081d46, following CT-L1/C04 P07.
**Owner scope update (19 Nov 2026):** expand the game beyond the originally locked three districts / twelve contracts to at least 200 locations, 200 levels and approximately 1,000 differentiated tasks, with human/controller playability tests deferred.

## Delivered source

- 25 original regions across residential, industrial, water, mountain, forest, coast and transport settings; 8 individually named sites in each region = **200 authored candidate locations**.
- One story-pinned dispatch per site = **200 level briefs**; each has a different puzzle-climate-infrastructure signature and five ordered tasks = **1,000 unique task IDs and descriptions**.
- Objective sequence: evidence investigation, safe power routing, locked repair, optional storytelling discovery and host-verified restoration. Each includes mechanic, tool intention, environmental hazard and a planned point weight.
- **200 lore-only collectibles** with unique IDs and optional discovery dependencies. No lootboxes, currency pickups or new host authority.
- Read-only searchable in-game dispatch atlas and deterministic seed-driven generator, with Python and GDScript validators for quantity, uniqueness, reference integrity and authority violations.

## Source and compatibility boundaries

The expansion is additive: no modifications to content/, existing C01–C12 solution or blueprint rules, host/grid/locks, networking, save, reward receipts or Steam. The original campaign content/campaign.json remains its twelve-contract first arc. The atlas lives under scenes/expeditions as **design metadata**, not authoritative contract content. Schematic local anchors are not spawn transforms, walkable geometry or certified clearances. Planned field points are not real credits; collectible definitions cannot award rewards.

## Verification

- python tools/build_dispatch_atlas.py --check
- python tools/validate_dispatch_atlas.py
- python -m unittest tests.python.test_exp01_dispatch_atlas -v
- bash tools/run_tests.sh and required GitHub Linux/Windows + Windows QA57 export
- Independent merged-main dual-OS CI after exact-head PR CI

The generator is read-only by default; explicit --write creates a timestamped backup before replacing the specific atlas file.

## Following production phases

**EXP02:** 200 region-specific scene layouts, landmark meshes and candidate colliders with source-based structural tests.  
**EXP03:** host-side mission task engine mapping approved task families to real intents, versioned progress and mission replay.  
**EXP04:** genuine collectible interactions, personal receipt deduplication, bounded points and preservation of old profiles.  
**EXP05:** branching campaign board, unlocks, difficulty, hand-authored scenario modifiers and accessible UI.  
**EXP06+:** content deepening, custom environmental narrative, art and mechanically distinct encounter design at all 200 sites.

No static brief or automated test silently establishes 200 playable levels. Physical traversal, human/controller, GPU, Steam F02/F06, save migration and release certification remain owner-held.
