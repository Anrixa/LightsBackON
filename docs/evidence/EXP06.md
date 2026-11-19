# EXP06 — Bespoke Level Mechanics, Environmental Hazards and Puzzle Diversity

## Engineering scope and authoritative baseline

- Baseline: EXP05 merge commit `b2861eecbf27d07c9ef348d681dc92c973a39178`.
- Project: `Anrixa/LightsBackON`, new expedition campaign only.
- EXP01: 25 regions, 200 distinct locations, 200 levels, 1,000 authored task briefs.
- EXP03: authoritative network-envelope host, grid, meter and repair actions.
- EXP04: host-only receipt rewards; lore has no power/credits effects.
- EXP05: host-gated branching progression and crash-recovery proof.
- This EXP06 work is **source-engineering only**, not a human/controller
  or release qualification.

## Committed encounter book

`scenes/expeditions/bespoke_encounters.json` contains exactly 200 explicit,
level-specific records source-bound to the immutable EXP01 title, location,
puzzle identity, site archetype, environmental risk, setting and first three
authored task mechanic motifs. Every record has a unique encounter key.

Eight active host puzzle families:

| Family | Server-observed solution requirement |
|---|---|
| fault_trace | Two WEST meter inspections spaced by an authored host tick interval |
| feeder_pulse | EAST feed accepted ON → OFF → ON sequence |
| post_repair_audit | WEST reinspection after genuine completed repair |
| stability_hold | Consecutive host-simulated supply ticks after restored repair |
| spur_isolation | GRID SPUR ON → OFF on actual switches |
| load_rebalance | EAST OFF → ON after WEST repair was restored |
| relay_coincidence | WEST inspection within bounded host ticks of accepted EAST ON |
| circuit_pair | EAST-on inspection before repair, then a further post-repair inspection |

Every puzzle additionally requires accepted WEST investigation, a genuinely
restored WEST work order and the live EAST circuit enabled. The authoritative
SessionHost still independently validates membership, command shape, rate,
sequence/dedupe, proximity, equipment and repair-state transitions.

Eight hazard families: water ingress, wind/gust lockout, static discharge,
thermal spike, signal interference, mechanical vibration, dust cloud and
equipment condensation. Each record pins an active/safe host tick schedule,
phase offset, hazard-restricted operation class and specific source hazard
description. Hazard restrictions refuse switch and/or repair actions without
changing the grid. No client may supply a hazard phase or hazard success flag.
Server-owned proximity to the worksite accumulates **diagnostic exposure
ticks**, not unverified damage, health effects or rewards.

The stage displays current source puzzle instructions, observed completion,
hazard state, next safe tick and host worksite exposure counter. The world
renders a temporary noncolliding visual hazard marker. This does not imply
physical traversal or collision certification.

## Integration and compatibility

- EXP06 is an explicit opt-in flag appended to the source-only expedition
  `ExpeditionHostSession.start()` signature. Legacy EXP03/EXP04/EXP05 calls
  without the flag keep their old behavior and session revision.
- The expedition stage opts into EXP06; session content negotiation now includes
  the EXP06 encounter fingerprint.
- The safety guard is an optional `SessionHost` callback invoked **after**
  ordinary host envelope/peer/sequence/dedupe acceptance and **before** any
  network command's simulation side effects. This preserves exact replay
  semantics even when hazard phases change.
- All `request_extract` intents are blocked until the configured puzzle is
  solved, even if the client forges or omits the entity name: existing extraction
  authority uses the actual mission zone, not the network entity ID.
- Accepted host actions advance EXP06 puzzle state; client-reported task IDs,
  timestamps, success booleans or simulated grid values cannot advance it.
- Existing EXP03 successful host solutions, all original C01–C12 contracts,
  source revisions, checkpoint schemas, personal currencies and existing saves
  are not rewritten or migrated.
- EXP04 rewards still require their original host task receipts. EXP06 creates
  no new reward type, no currency, no save file and no score multiplier.

## Required automated qualification

1. Independently validate all 200 source-bound records using
   `python tools/validate_exp06_encounters.py` and mutation-denial tests.
2. Run `test_EXP06_bespoke.gd` via the existing automatic Godot test runner:
   all 200 content pins, eight live host action puzzle families,
   malformed/source-forgery rejection, extraction denial until evidence,
   environmental action lockouts and no-replay side effects.
3. Re-run original EXP01–EXP05 automated integration and Python reference tests,
   including 200 legacy EXP03 host solutions and all original C01–C12 traces.
4. Run full Linux and Windows GitHub Actions, Windows export/smoke and QA57
   source pinning.
5. Record tested commit SHA, CI run URLs, results and exported artifact hashes
   before making any source-engineering certification assertion.

## Explicit HOLD

Physical route traversal, human/controller playability, visual signoff, real GPU
performance, hardware/network/Steam multiplayer, anti-cheat assurance and
production/release certification remain held. The 200 source configurations
share eight implemented puzzle families with individual parameters and
hazard schedules; **200 fundamentally unrelated puzzle engines are not claimed**.
The next fidelity pass can add more authored interactables and specialized
geometry once these authority/CI gates are qualified.
