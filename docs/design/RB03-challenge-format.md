# RB03: challenge format, solver and checks

Decision: `docs/adr/ADR-019-designed-locations-and-challenges.md`. Plan: `docs/design/RB-locations-and-challenges-plan.md`.
Evidence: `docs/evidence/RB03.md`.

A **challenge** is a data record on an authored location. A **solution trace** is a list of abstract player steps. Both runners
replay a trace and must produce the same canonical string after every step, byte for byte:

- Python: `reference/lbo_challenge.py` (`Run`). It also holds the schema validator, the solver, the scoring and the pillar checks.
- GDScript: `scripts/simulation/challenge_runner.gd`. It runs no scene tree and uses `power_grid.gd`, so its power rules are the host's.

The power rules are those of CLAUDE.md section 3, unchanged: integer PU, 10 Hz ticks, refuse before mutation, trips after
`trip_ticks`, refused resets, and ADR-003 canonical serialization.

## Files

| Path | What |
|---|---|
| `content/challenges/rules.json` | Pace (`action_ticks`, `carry_ticks`), wait cap, default crew scaling, par margin, solver limits, marker-policy limits, score weights, tier thresholds |
| `content/challenges/<location>/<id>.json` | Shipped challenges (RB04 onward; none yet) |
| `tests/data/challenges/*.json` | Fixtures: `rb03_marker_only`, `rb03_no_tradeoff`, `rb03_storm_shift` |
| `tests/data/challenges/traces/` | Golden solution trace with pinned final hashes per crew size |
| `tests/data/challenges/probes/` | Refusal probe (`must_solve: false`) |
| `tools/rb03_challenge_check.py` | Solves, scores, pillar-checks and cross-checks everything; it is part of `tools/run_tests.sh` |
| `tools/godot/validate_solution.gd` | `--challenge=<file> --trace=<file>` or `--manifest=<file>` prints `STEP`/`FINAL` records |

## Challenge record (schema 1)

All numbers are ints. Every ID matches `^[A-Z0-9_]+$`, and IDs are unique across nodes, edges, faults, switches, temporary supply,
latches, routes, flood areas and storm events.

| Field | Meaning |
|---|---|
| `schema`, `id`, `location_id` | `1`, the challenge ID, the location it is authored on |
| `grid` | `trip_ticks`, `nodes`, `edges`, `protections`, optional `module_upgrades`. Same format as a contract `grid.json` |
| `grid_sources` | The sources that count as grid supply. With more than one, an overloaded source is not valid supply |
| `required_consumers` | Must all be on grid supply for `verification_ticks` continuous ticks |
| `excluded_loads` | Never count toward anything |
| `faults` | `{id, panel, junction, fix, access, work_ticks}`. `fix` is a grid `set` of `failed`/`tripped` (junction), `healthy`/`enabled` (edge) or `online` (source), or a whitelisted `replace_module`. `access` is "" or a grant or flood-area ID |
| `switches` | `{id, target, field}` with a player-settable field: junction `isolated`/`tripped`, consumer `enabled`, edge `enabled` |
| `temporary_supply` | `{id, source, start_anchor, anchors: [{id, storage, routes}]}`. The source starts offline, routes start disabled, and the start anchor is a storage anchor |
| `latches` | `{id, consumer, source?, supplied_ticks, grants}`: continuous valid supply grants access and latches; switching off does not undo it |
| `access_routes` | `{id, grants, requires_latch}`: ladders and hatches. Using one is a step, and the grant persists |
| `flood_areas` | `{id, water_cm, wade_cm, drained_by}`: reachable while `water_cm <= wade_cm` or once the drain latch has latched |
| `storm_events` | `{id, tick, kind}`. `grid` breaks something (`cmd` is edge `healthy=false`, junction `failed=true` or source `online=false`). `close_route` closes `route` from `tick` to `until_tick`. `flood` sets `area` water to `water_cm` unless it is drained |
| `verification_ticks` | Length of the final verification window |
| `crew_scaling` | `{"1": 100, "2".."4": pct}`. Repair work and carrying take that percentage of the solo time. The values never rise |
| `par_ticks` | Shipped challenges only: `ceil(solved_tick(crew) * par_margin_pct / 100)` for each crew size, as measured |

A story contract maps onto this format through `from_contract()`. It keeps the grid, repairs, switches, generator anchors,
access latches, ladders (as access routes) and the C09 wind closure (as a `close_route` storm event). It leaves out optional
objectives, stars, venues and the finale, because those are not part of the puzzle.

## Steps (solution traces)

Every non-wait step then costs `action_ticks`. Every step may carry `expect` (default `"ok"`).

| Step | Effect / refusals |
|---|---|
| `{"do":"repair","id"}` | Isolate the junction, spend `work_ticks` × crew %, install the fix, then restore (un-isolate and reset the breaker). A refused reset re-isolates. Refusals: `ACCESS_BLOCKED`, `ALREADY_RESTORED`, grid codes |
| `{"do":"switch","id","value"}` | Sets the field. Refusals: `NO_CHANGE`, grid codes (`DUAL_SUPPLY`, `RESET_OVERLOADED`, ...) |
| `{"do":"place","id","anchor"}` | Moves the temporary supply (carry ticks × crew %). Refusals: `SUPPLY_RUNNING`, `ROUTES_CONNECTED`, `UNKNOWN_ANCHOR`, `NO_CHANGE` |
| `{"do":"route","id","edge","on"}` | Connects or disconnects a cable at the current anchor. Refusals: `ROUTE_NOT_AT_ANCHOR`, grid codes |
| `{"do":"power","id","on"}` | Starts or stops the source. Refusals: `NOT_PLACED` (at a storage anchor) |
| `{"do":"access","id"}` | Uses a route. Refusals: `ACCESS_NOT_READY`, `ROUTE_CLOSED`, `NO_CHANGE` |
| `{"do":"wait","ticks"}` / `{"do":"wait","until":"latch","id"}` / `"verified"` / `"solved"` / `{"until":"tick","tick"}` | Waits. A condition that does not arrive within `wait_limit_ticks` gives `WAIT_TIMEOUT` |

**Tick order.** On each tick: storm events for that tick, then `grid.step()` (trips), then latches (in ID order), then the
verification counter. The challenge is **solved** at the first tick where it is verified and every temporary supply sits at a
storage anchor.

**Canonical string.** It is `serialize({"grid": grid.canonical_state(), "run": {...}})`, where `run` holds the fault states
(0/1/2), grants, latched ticks, latch counters, verification counter, solved tick, anchors, used routes and water levels.

## Solver

- **Search.** A* over steps for a crew of one. The cost is ticks, and the bound is the remaining verification window combined with
  the stowing cost.
- **Pruning.**
  - States with the same discrete key are pruned by dominance on the latch and verification counters.
  - The solver never switches on a load that is neither required nor a latch target.
  - It never takes a step that is refused or that leaves any source or edge overloaded.
- **Result.** The result is `solved`, `unsolvable` (the whole reachable space was searched) or `limit`. A `limit` result is never
  read as proof that no solution exists.
- **Hardening.** `harden()` then replays the trace for crews of 2 to 4. A bigger crew works faster, so a step that relied on time
  passing can arrive too early. Before such a step it inserts the latch wait, or the tick wait, that the step depends on. The solo
  crew loses no time. The answer is the same trace for every crew size.

## Difficulty (measured from the solution)

| Metric | Definition |
|---|---|
| `steps` | Non-wait steps in the solution |
| `tradeoffs` | Routes energized from a temporary supply. A supply counts only when it is required (the challenge is `unsolvable` without temporary supply) and contended (one anchor's routes demand more than its capacity) |
| `failing_routes` | Distinct steps, offered at some state along the solution, that are refused or would overload |
| `meter_readings` | Fault panels the dark-building markers cannot point at (trunks, sources, modules), plus the distinct elements those traps would overload |
| `time_pressure` | Storm events that happen before the solo finish |

`score = Σ weight × metric`, and the tier is the highest tier whose `tier_min_scores` threshold the score reaches. Weights and
thresholds are design choices calibrated on C01-C12 (C01 = 28, tier 2). Whether the tiers *feel* right needs people.

## Pillar checks (a failure rejects a challenge)

- `MARKER_ONLY`: a scripted player who only follows markers and holds Interact finishes the challenge, or the solution needs no
  meter reading.
  - That player repairs anything reachable and takes every open route.
  - It sets every switch to its "on" sense and connects every cable at the first pad.
  - It starts the generator and stows once everything is lit.
- `NO_TRADEOFF`: there is no temporary supply, the challenge is solvable without it, or the supply can carry every route at once.
- `NO_VISIBLE_RECOVERY`: every required consumer is already on grid supply at the start.

## Duplicates

- `puzzle_hash` is the challenge without its names, notes, par and source pin. It catches exact duplicates.
- `near_duplicate_hash` is the sequence of boolean state shapes along the solution: every supply flag and run fact, with no numbers.
  It catches the same puzzle with re-tuned capacities.
- Within a shipped set, the later challenge (in ID order) whose hash matches an earlier one is rejected.
