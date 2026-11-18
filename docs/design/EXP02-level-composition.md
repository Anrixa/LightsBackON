# EXP02 — 200 schematic 3D graybox levels and distinct load plans

**Source:** EXP01 merged main c42f37bb097e9fdf4bd930ccff23e93dbdbfaa09.
**Scope:** geometry-composition code, not playable campaign or reward authorizations.

## Source implementation
- scripts/world/expedition_layout_plan.gd creates a distinct 52m x 52m candidate layout from each of the 200 authored level+location pairs. Every plan has five spatially separated worksite station markers linked to the 1,000 source tasks.
- Each candidate returns a numerical power-routing trade-off: three required loads, west/east feeder limits, a separately rated optional bypass, a deliberately unsafe west shortcut, source capacity and a proposed host verification duration. This is **planning math, not a session-host simulation or certification**.
- scripts/world/expedition_graybox.gd creates a fresh 3D floor, a single grounded box collider, roads, distinctive industrial/health/water/transport/market/education/shelter/communications landmarks, environmental hazard dressing and marked stations. Each world uses authored source identity and its own derived style; no third-party images/meshes.
- The EXP01 dispatch catalog now renders just one selected graybox in a 3D overhead viewport, replacing it on selection rather than loading all 200 simultaneously.
- Tests: all 200 source plans, unique layout fingerprints, all 1,000 bounded stations, numeric safe/unsafe capacity guards, all 200 real Godot 3D scene constructions, UI preview replacement, and foreign/fake-authority rejection.

## Isolation
This phase changes no original C01–C12 contract content, authoritative grid/mission/repair rules, save format, reward receipts, collision in existing live maps, Steam/network, player/controller physics or main campaign. Stand positions and paved ribbons are **candidates**; no continuous player movement, obstacle sweep, human readability or camera UX are certified.

## CI gates
Run full Linux/Windows suite, 12 solution replays and reference parity; Windows QA57 export/smoke; then independent merged-main CI. Recording of verified runs belongs in docs/evidence/EXP02.md after results. Existing physical/human/controller/GPU/Steam/production holds remain.

## Follow-on phases
EXP03 must implement validated real host command transitions and level task completion without letting task preview data decide power or rewards. EXP04 must use the existing personal receipt/deduplication model for genuinely interactable discoveries and bounded points. Neither is implied by this scene preview.
