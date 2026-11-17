# CT-L2 / C05 — Canal Yard Pump Access (provisional authored content)

17 November 2026. ADR-017 allows logic/data development ahead of canonical CT04; **not** official CT04 certification.

The repository's primary CT04 acceptance requires no pump deadlock and optional rewards that never block completion. Original C05 PDF contract sheet is currently unavailable to this work environment, so the following precise figures/title are **new authored candidate values**, not verified claims about blueprint pages 18–21. They must be reconciled before canonical content approval.

## Core host-authoritative scenario

The Canal Yard yard has five required services (19 PU): Dock Office 4, Crane 4, Cold Store 5, Yard Lights 3, Workshop 3. A 24 PU grid supplies two independent 12 PU feeders. DOCK starts failed/tripped, COLD's feed cable starts damaged. Both repair panels are behind separate flooded access rooms. Portable GEN has 6 PU and two separate 4 PU pump routes; attempting both simultaneously loads 8/6 and trips TEMP after 15 continuous grid ticks. One pump at a time is the recoverable, safe route.

Powering dock pump continuously for 80 ticks grants DOCK_DRAINED; cold-yard pump continuously for 100 ticks grants COLD_DRAINED. These are **independent durable access latches**. The player cannot lock either repair before its own latch. After isolation/meter/part replacement, DOCK supplies 8 PU, COLD supplies 11 PU. The 2 PU optional dock beacon brings DOCK to 10/12 and total GRID to 21/24. Leaving it dark must not block finishing.

Existing host-only repair state machine, single-player/cooperative-capable command route, no player-authored supply state, one source per tree, generator storage/recovery and mission verification (100 ticks) plus extraction (50 ticks) are retained. No added scripted engine logic is required, only definitions and tests.

## Scope and invariants

- Eight JSON definitions with stable IDs and localization/tablet entries.
- Provisional logical storage/work-pad anchors have no physical coordinates. No Canal Yard scene, final navigation, real pump animations, water-height visuals or physical distances are claimed.
- 100% completion via replayed host intents; wrong route overload and reset; both access latches independently enforced and durable; missed optional remains completable.
- Existing C01–C04 content left unchanged. C05 changes global ADR-018 rules revision: older saves are preserved and may be rejected; no migration or deletion.
- Contract name/PU/ticks must be compared against original blueprint C05 sheet before certification.

Full measured evidence and open gates are in `docs/evidence/CTL2-C05.md`.
