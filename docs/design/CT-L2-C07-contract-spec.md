# CT-L2/C07 — Wrong Label (authoritative blueprint-aligned design)

- Source: original `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf`, pp.18 and 20, **read from repository PDF** on 17 Nov 2026.
- Authority: ADR-017 independent content-logic track. Canonical `docs/backlog.json` CT05 remains NOT_STARTED behind CT04. Not a release or physical-level certification.
- The original source explicitly calls C07 **Wrong Label** and specifies a 10 PU installed protection module vs stale 14 PU label, required east demand 12, replacement 14 PU part, and a meter-inspection-before-first-reset bonus.

## Required power network

Baseline Canal Yard grid: 30 PU source, west feeder 14 PU, east feeder normally 14 PU, generator 8 PU. West has LAUNDRETTE 5 PU, DINER 4, ROW_HOUSES 4 (13 total), all supplied on load. East has DEPOT 4, COLD_STORE 5, PUMP_KIOSK 3 (12 total), initially dark with JE tripped and E_GRID_JE currently rated 10 PU. A stale physical JE plate displays 14 PU, which is not authoritative.

The **meter at PANEL_JE** reports actual `capacity_pu=10` and `demand_pu=12`, which is both the accurate diagnostic and the evidence required for the optional. Resetting JE in this state is refused atomically with `RESET_OVERLOADED`. Shedding COLD_STORE permits a temporary 7/10 reset, but returning the missing load reproduces a 12/10 overload after 15 host ticks: this is not the solution.

## Proper repair

A protected feeder module upgrade is contract-whitelisted: `E_GRID_JE` from exactly 10 to exactly 14 PU, with breaker JE isolated. The original repair lock, meter-first diagnosis, 8-step repair state machine, supplied single `MODULE_14PU`, tools and final test are mandatory. Generic `set capacity` remains prohibited; no client can submit this operation as a host intent. `PowerGrid.apply(replace_module)` accepts only an existing contract-declared protected edge, isolated breaker and exact replacement rating, and refuses arbitrary or repeated replacements.

Save `causes()` carries the upgraded edge capacity. `restore_causes()` now permits only the contract-authorized 10→14 transition, rejects other persisted ratings without mutation, and recomputes all derived flows. Earlier contracts have no module whitelist and their save/mission field shapes are unchanged.

## Evidence bonus

Optional `EVIDENCE_MISMATCH` is earned only when the host accepts an **actual JE meter inspection** showing 10 PU actual rating and 12 PU demand before the **first in-range reset attempt**, including resets correctly refused for 12/10 overload. A wrong reset does not make the mission unwinnable: complete the replacement normally, but no optional evidence star can be retroactively claimed. Host mission state records booleans `observed` and `reset_attempted` conditionally for C07; both are durable and validated atomically at restore. The normal six required services must remain on GRID for 100 ticks, portable equipment stowed, crew at van extraction for 50 ticks.

Three-star no-trip completion and two-star missing-optional completion are independent of the physical plate. The note/label is environmental misinformation, **not** a meter override.

## Explicit limits

This phase supplies headless data, state transition and automated tests. It does not provide 3D Canal Yard geometry, plate UI scene, release-level pad positions or physical keyboard/controller trials. The 8 PU generator has an optional depot socket but stays stowed in the known solution. V09/D08, Steam F02/F06 and target GPU checks are separate.

During source recovery the previously provisional C05/C06 content was found **not aligned with the original sheet**; detailed differences and the required corrective phase are recorded in `docs/evidence/CTL2-BLUEPRINT-RECONCILIATION.md`. No earlier contract content was silently rewritten or promoted.
