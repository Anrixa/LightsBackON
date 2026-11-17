# CT-BP/C05 — Rising Water original-blueprint correction

**Authority:** Development Blueprint v1.0 pp.18–19; `docs/design/CT-BLUEPRINT-CORRECTIONS.json`. **Date:** 17 November 2026. **Status:** implementation under independent CI verification, NOT physical/playable or release certified.

## Required puzzle

- Canal Yard GRID is **30 PU**, WEST and EAST feeder capacities **14 PU** each. Permanent required west-side services: LAUNDRETTE 5, DINER 4, ROW_HOUSES 4 = **13 PU**. East-side: DEPOT 4, COLD_STORE 5, PUMP_KIOSK 3 = **12 PU**. Full supply **25/30 PU**.
- Both GRID→WEST and GRID→EAST feeder trunks start **damaged**; their downstream junctions are not falsely marked as fuse failures. Each flooded room has its own edge-repair, isolated host-authorized panel and a separate cable-splice supply. Separate flooded access gates cannot be repaired until the correct pump earns its own host-owned access latch.
- GEN is **8 PU**. WEST pump uses **5 PU**, EAST pump **4 PU**. Each requires **120 uninterrupted 10 Hz host ticks**. Either sequence is valid. Running both draws 9/8 and trips the temporary branch after 15 continuous overloaded ticks.
- Generator route and all repairs are host intents with meter-first isolation. Both pump access grants are durable and independent. Final verification is 100 GRID-supply ticks, then equipment stow and a 50-tick cancellable extraction.

## Optional pickup-timed objective

COLD_STORE is mandatory for final restoration, **not an optional electrical load**. A separate bonus is awarded if GRID supply reaches COLD_STORE within **1,800 host ticks (180 seconds)** beginning with the **first successful equipment pickup**. Neither briefing/loading nor failed pickup intents start the deadline; duplicate/second pickups never restart it. The timer is derived from host grid ticks, not client/UI clocks or absolute host time. A missed bonus does not stop repairs, verification, extraction or two-star completion.

The host records `pickup_deadline` in its canonical mission state with the remaining ticks for the HUD. The durable checkpoint stores only `started`, `elapsed`, `on_time`, and `missed`. Invalid/missing conditional records fail closed before state mutation. Earlier contract checkpoint shapes remain unchanged; **old deployed C05 checkpoints have NOT been migration-qualified**.

## Tests and acceptance boundary

The new C05 suite asserts exact capacities, demands, initial faults, solution replay and scoring, 119/120 access boundaries, both pump orders, 9/8 overload trip/recovery, same-tick latch reset, triggering conditions, time miss that still finishes, save roundtrips/forgery, invalid definitions, and unchanged C01–C04/C06–C08 mission formats. Full cross-contract solution replay and independent Linux/Windows CI must pass on the **exact final PR head**, followed by merged-main CI before source fidelity status can be raised.

Prior `docs/evidence/CTL2-C05.md` remains as historical provisional testing evidence. No save, asset, physical world or other contract is deleted or migrated. This branch does **not** satisfy Canal Yard scene/controller/human/GPU/Steam F02/F06 or production release certification.
