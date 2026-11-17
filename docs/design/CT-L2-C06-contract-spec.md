# CT-L2 / C06 — Cold-Chain Window (headless contract logic)

**Authority:** ADR-017 (independent content logic, not canonical CT04 approval). Source base: `42f1ee718dd8f4ed0561723a67505342547b4769`. Date: 17 November 2026.

**Provenance limitation:** The original 46-page development blueprint's C06 contract sheet could not be extracted through the available repository connection, and the user did not provide the original design-sheet text. The title, PU allocations, 280-tick grace window and exact services are newly authored **provisional** values, subject to mandatory source reconciliation before final content sign-off.

## Contract mechanic

C06 retains the Canal Yard portable-generator puzzle and distinct 80/100-tick pump access latches, but changes the optional objective from C05's beacon to the **cold store itself**. The cold-store 5 PU consumer begins disabled; its dedicated switch is a host-authored command. Mandatory grid services are Dock Office 4 PU, Crane 4 PU, Yard Lights 3 PU and Workshop 3 PU (14 total). Turning on the optional Cold Store adds 5 PU, yielding 19/24 PU on GRID, 8/12 PU at DOCK and 11/12 PU at COLD.

The independent flood latches must grant dock/cold repair access before the original meter-first repairs can proceed. The 6 PU generator has two disconnected 4 PU temporary pump routes. Activating both causes an 8/6 PU overload and breaker trip after 15 ticks; isolating a route and resetting the breaker recovers. With staged pumping, the cold feeder can be repaired without deadlock.

An **optional bonus only** is granted if COLD_STORE receives GRID supply **on or before host tick 280** (28 s at 10 Hz). Supplying it at tick 281, later, or never must *not* block four-service verification (100 ticks), generator return, extraction (50 ticks), core completion or the non-optional two stars. The bonus timing is a target to playtest, not an evidence-backed human deadline.

The deadline is tracked by the existing `MissionDirector` `optional_deadline_ticks` and durable `optional_first_supplied`. There is no new simulation code or new save schema. The event must be a genuine host-observed on-GRID supply transition, not client-reported time or temporary generator supply.

## Acceptance

The exact-tick boundary, one-tick-late bonus loss, optional skipped, generator overload/recovery, independent access latches, forged deadline/save rejection, full solution and legacy C01–C05 contract loading must all pass on Windows and Linux with the full suite. Solution replay uses actual host command envelopes. Physical scene, controller, GPU and Steam behavior remain outside the scope.

C06 adds new rules files, changing the global ADR-018 rules revision: existing checkpoints may be refused but are preserved; no silent migration or deletion is authorized. Canonical CT04 remains at NOT_STARTED pending CT01/CT03.
