# CT-BP/C04 — The Whole Block: original-blueprint correction

**Authority:** `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf`, contract C04, pp.18–20; `docs/design/CT-BLUEPRINT-CORRECTIONS.json`. Supersedes the provisional sign-spur specification in `docs/design/CT-L1-C04-contract-spec.md`. Provisional evidence remains preserved, not overwritten.

## Contract topology and start state

- `GRID` online 24 PU; five required services are `APT_W` 4, `MARKET` 5, `PUB` 4, `APT_E` 4, `WORKSHOP` 3 = 20 PU. West 9/12 and east 11/12.
- `JW` west fuse begins failed and tripped, and the direct `GRID→JE` east trunk begins damaged. Repair both with existing meter-first host-locked state machines.
- No C01 pump access gate or generator duty is required.
- `SIGN` demand 3 PU remains optional. The dangerous existing `JE→EAST_SIGN→SIGN` path requires explicitly opening the east-sign isolator: east rises to 14/12, causing a protection trip after 15 continuous overloaded ticks.
- The safe independent GRID sign feeder has a **4 PU** rating, represented as `E_GRID_SPUR` 4 PU (disabled initially) then `E_SPUR_SIGN` 4 PU. An explicit isolated `R_SIGN_SPUR` cable installation (meter, tools, host lock and SPUR isolation) enables this pre-authored feeder; the cable is a permanent network repair, not portable equipment.
- East route stays isolated when using the independent feeder. A simultaneous energized sign route is refused **before state mutation**. Valid outcome: GRID 23/24, west 9/12, east 11/12, sign spur 3/4.

## Optional continuity and durability

- `LATCH_SIGN_SUPPLY` grants optional sign completion only after **100 uninterrupted valid GRID-supply ticks** to SIGN.
- The host observes each accepted switch/equipment/repair intent as well as each 10 Hz grid tick: an off/on interruption within one tick clears unsatisfied progress.
- Invalid source, overload, branch trip or loss of supply cannot progress the latch. Latch completion is durable; partially accumulated ticks are validated during restore. Forged/out-of-range counts and receipts are rejected without altering state.
- This is an **optional bonus**. Missing it never prevents 100 ticks of mandatory supply verification or 50-tick extraction. The permanent installed feeder must not interfere with portable equipment stow.

## Implementation/test obligations

Run `bash tools/run_tests.sh` including all C01–C08 full host solutions, negative route tests, exact 99/100 boundaries, same-tick drops, breaker trip, save validation and all earlier contracts. Require independent exact-head Linux and Windows CI and separate merged-main CI before claiming source-aligned headless acceptance.

**Ceiling:** No physical scene, playable 3D sign cable, HUD, human/controller, target GPU performance, old-release C04 checkpoint resume or two-network Steam certification can be inferred from headless code/CI. No save deletion/migration and no release promotion.
