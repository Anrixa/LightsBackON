# EXP019–EXP021 consolidated integration and qualification record (2026-11-23)

## Scope and ancestry

- Consolidated from qualified main `47e3a5949fa4efc1061025a9097de391d0be3b44` with EXP019 A01–A05 already merged (PR #298).
- EXP020 A01–A05 source ancestry: `9e63f5009476ddff7b79e66ef581b28dd2ce57e1` (PRs #287/#288/#290/#292/#294).
- EXP021 A01–A05 source ancestry: `ac1473b39ba53ac8bb8cd8fdf3e4e10a4943fdb3` (PRs #299–#303).
- This integration replays the additive source changes; it **does not** replace the newer EXP018/EXP019 host runtime, protection gates, physics, or authenticated rules with stale EXP020 versions.
- Unmodified protected contracts, canonical 200-level/1000-task atlas, save/network/ledger legacy paths, and original 12-contract progression are retained.

## Reconciled conflicts

1. `expedition_mission_stage.gd`: retain EXP018 owner opt-in, EXP019 host-validated startup/physical site/collision/tool procedures and host projections; add EXP020 work orders, ledger read-only projections, pause/retry/field guidance; attach EXP021 art batching, audio and restoration projections independently.
2. `tools/run_tests.sh`: retain complete EXP015–EXP018 inherited source gates and EXP019 200-scene physics route validator, add EXP020 parser preflights and EXP021 headless evidence gates.
3. `.github/workflows/ci.yml`: retain existing Linux/Windows source and Windows release-export checks; add EXP019 reachability evidence and EXP021 exact-head EXE/PCK checks.
4. Detached-scene Godot error fixes: compute relative MultiMesh transforms through local ancestors; place host-accepted 3D audio cues without requesting detached global transforms. The focused CI now fails on Godot engine errors.

## CI and release gates

- EXP019, EXP020, EXP021 heads separately passed published source CI before consolidation; **not** evidence that this combined tree passes. The combined head must pass fresh Linux and Windows full CI, focused EXP021, Godot scene/host regressions, and Windows export source/hash/boot checks.
- 25 regions, 200 scenes/hosts, 1000 task IDs are SOURCE/HEADLESS scope; they do not prove 200 MissionDirector completions or human/controller traversal.
- Known predecessor full CI leaks (572 CanvasItem RIDs and 1444 ObjectDB instances at exit) and one inherited detached `intent_outbox.gd` engine log must be triaged separately; do not represent those legacy warnings as production certification.
- GPU frame-time/p95, real-memory profiling, two-client Steam, physical traversal, controller usability, human evaluation and release stay HOLD pending independent evidence and owner authorization.
- Avoid tags or final release until all qualified gates are evidenced. Nothing here changes owner save data or requires a destructive migration.
