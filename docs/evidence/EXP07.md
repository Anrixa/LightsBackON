# EXP07 — Bespoke Interactables and Advanced Puzzle Systems

**Scope:** additive, opt-in source-engineering expedition devices for 200 EXP01 levels, stacked on the pinned EXP06 draft commit `fdf4c968c345405fd66525f8d3f2e62073b60ab8`.

## Deliverables

- `scenes/expeditions/bespoke_device_graphs.json`: 200 level-specific graphs; 1,100 graph nodes; five- and six-node variants, 100 each; eight source-pinned site domains and their distinct operations.
- `scripts/gameplay/expedition_device_graph.gd`: host-owned device states (`idle`, `jammed`, `done`), dependency gates, real host-evidence prerequisites, premature-action jam, prepared reset, final multi-device completion.
- `scripts/network/session_host.gd`: `operate_device` is admitted only through the existing byte-envelope checks, membership, session binding, sequence/replay cache, rate gate, opt-in policy, server-owned range/sight and session authority. Canonical host state/hash includes device state when the EXP07 extension is installed. No legacy campaign installs it.
- `scripts/gameplay/expedition_host_session.gd`: EXP07 is a new **opt-in** `enable_devices` argument; EXP06 must also be enabled. Source fingerprint and real graph validate before the session starts. The last mission/extraction cannot start unless the graph is solved. Device evidence comes from the real WEST meter inspection, EAST grid circuit and restored WEST repair.
- `scripts/gameplay/expedition_mission_stage.gd`: on-demand first-person 3D source devices at host-bound workstations, available actions and safe reset on jam, with an updated diagnostic HUD. Physical traversal remains unqualified.
- `export_presets.cfg`: includes EXP06 **and** EXP07 JSON books in Windows exports. This also closes a source-export omission in the inherited EXP06 draft.
- `tools/validate_exp07_device_graphs.py` and `tests/python/test_exp07_device_graphs.py`: full 200-graph integrity and mutation gates, independent deterministic solution/failure/recovery reference replay, 1,100-node count, export inclusion checks.
- `tests/integration/test_EXP07_devices.gd`: Godot session startup for all 200 configurations, real host entrypoint, duplicate/forgery/range gates, recoverable jam, host evidence requirements, additional extraction interlock, opt-in isolation. Runs with the full original Linux and Windows suite through `tools/run_tests.sh`.

## Mechanically distinct scope

The graphs have differing device actions, source infrastructure, topology, prerequisite order, five/six-device layouts, mandatory host-derived milestones and failure/recovery state transitions. This is **not** a claim of 200 entirely independent puzzle engines or human-qualified experiences. They are 200 authored device-graph instances running on a shared validated execution engine. Further bespoke art, physics, puzzles and route work belongs to later EXP phases.

## Authority boundaries

- Existing C01–C12 contracts, production saves, credit balances, existing EXP04 ledger and rewards, and campaign progression remain unchanged.
- No client-provided position, tick, graph, prerequisite, state, repair success or extraction success advances EXP07.
- The one-action payload contains only an author-whitelisted operation string; source-configured graph nodes are never accepted from clients.
- The accepted premature fault is a real host state transition, reflected in canonical revision and dedupe cache. A duplicate packet cannot fault twice.
- EXP07 devices are opt-in and separate from EXP06 puzzle and hazard gates. Both gates must pass before extraction.

## Qualification gates (not all yet passed)

1. Validate all 200 graph identities and all 1,100 unique device IDs independently in Python and Godot.
2. Exercise real host envelopes, jam and reset semantics, 200 level initializes, EXP06 puzzle completion and EXP07 extraction refusal.
3. Full original F03/F04/C01–C12 and EXP01–EXP06 regression, reference parity and solution traces.
4. Independent Linux and Windows GitHub Actions exact-head CI, Windows export/smoke and QA57 source/resource checks.
5. Review commit SHA and preserve all negative evidence before merging. EXP06 PR #191 must be qualified first, and this EXP07 PR is stacked on the EXP06 branch.

**Explicit HOLD:** continuous human/controller physical traversal and collision qualification; real GPU performance, Steam/F02/F06 multiplayer, released checkpoints/migrations, production release and art/signoff. Automated source qualification must not be misrepresented as those held tests.
