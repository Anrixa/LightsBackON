# CT-L2 source-reconciliation finding — C05/C06

- Observed 17 Nov 2026 by extracting the **original** `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf`, pp.18–20, within the connected repository.
- This corrects the previous status notes claiming the PDF could not be accessed.
- C05 and C06 remain `CLOUD_VERIFIED` **only for their independent provisional host-logic implementations**; the original blueprint compliance gate is **HOLD_CONFIRMED_MISMATCH** for both. Their measured CI results remain factually valid but are not evidence of following the original design.

## C05 Rising Water (pp.18–19)

Original: Canal GRID 30, west/east feeders 14, GEN 8; LAUNDRETTE 5, DINER 4, ROW_HOUSES 4 (13); DEPOT 4, COLD_STORE 5, PUMP_KIOSK 3 (12); both trunks broken behind independently flooded task areas; pumps 5 and 4 PU, each **120 continuous ticks**. Optional cold store restored inside **180 seconds from first equipment pickup**; either pump order must solve. Existing provisional C05 differs materially in topology, demand, generator, latch durations and optional objective. A dedicated corrective implementation and new tests are required.

## C06 Cold Chain (pp.18,20)

Original: same Canal baseline (25 PU required), west healthy, east trunk broken, **one 4 PU access pump for 120 ticks**, generator 8. Two mutually exclusive cold-store temporary/grid paths; cold store demand 5 plus pump4 exceeds GEN8. Optional *cumulative cold-store unpowered time* must stay below **120 seconds**, pausing while supplied but never resetting. Existing provisional C06 uses a first-power deadline and different required load/topology, so is not blueprint-compliant. The correct cumulative-outage timer needs its own durable host simulation and tests.

## Corrective gate (separate phase, non-destructive)

1. Keep C05/C06 existing sources and passing CI evidence intact until corrective source, trace and tests exist.
2. Build corrective changes on dedicated branches with exact baseline, 2 pump orders / exclusive generator route / cumulative timer semantics, strong negative tests, cross-contract regressions, and exact-head Linux/Windows CI.
3. Never silently mark CT04 DONE; official CT01/CT03 gates and physical Canal Yard acceptance remain unqualified. Do not delete old saves or migrate them without explicit owner authorization.

## Additional confirmed discrepancies — Alder Street

The recovered PDF pp.18–19 also reveals original specification differences in previously cloud-verified **C02–C04**. Their Linux/Windows simulation results remain valid for their existing authored implementations, **not** evidence that they match the original contract sheets:

- **C02 Dinner Rush:** Blueprint requires both MARKET and PUB to receive 10 continuous seconds of valid supply before 180 s. Existing `content/contracts/c02_dinner_rush/mission.json` has optional `SIGN` only and `optional_deadline_ticks=2400` (240 s).
- **C03 Roof Route:** Blueprint requires a west-fed access-light latch of 5 s before ladder access and an optional 2 PU roof work light for 10 continuous seconds. Existing `content/contracts/c03_roof_route/mission.json` has no `access_latches` and describes an optional 1 PU roof beacon.
- **C04 The Whole Block:** Blueprint calls for the direct GRID-to-SIGN spur to be rated 4 PU with a 10-second supply objective. Existing `content/contracts/c04_whole_block/grid.json` defines `E_GRID_SPUR.capacity=3`; there is no original 10-second optional latch.

C01 was not re-audited in this source-recovery pass. These discrepancies do **not** invalidate past CI execution; they invalidate any inference that C02–C06 are faithful to the original authored sheets. Prioritize dedicated non-destructive C02–C06 fidelity fixes with new solution traces and both OS CI. Keep official CT03/CT04/CT05 dependencies unchanged.
