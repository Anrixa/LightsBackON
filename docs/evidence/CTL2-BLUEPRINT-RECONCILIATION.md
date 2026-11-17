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
