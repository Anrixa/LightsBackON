# CT-L1 / C04 — The Whole Block (contract-logic candidate)

17 November 2026. ADR-017 authorizes original **logic/data** development while official CT03 remains gated by D08. Source base: `d8de4050592c4db3893c60e83e05188b19a4220a`.

## Puzzle and capacities

- Five mandatory Alder services: west 9 PU and east 11 PU, total 20 PU on the 24 PU GRID.
- West fuse begins failed/tripped; east 12 PU feeder begins broken. Host-authorized meter-first repairs restore each.
- The Lantern sign is an **optional 3 PU** load. The east feeder is already at 11/12 PU. Enabling its sign branch, after opening the EAST_SIGN isolator, gives 14/12 PU and trips the JE protection after 15 ticks.
- An independent 3 PU `GRID → SPUR → SIGN` feed provides a safe route. The separate sign splice is damaged, needs isolated repair, and the sign switch starts off. The east sign branch runs through the separate EAST_SIGN junction, initially isolated to avoid two simultaneous routes. Its host-controlled isolator must stay closed to use the direct feed safely.
- Safe resolved loads: west 9 PU + east 11 PU + sign 3 PU = **23/24 PU** at GRID; east 11/12; spur 3/3. Activating both sign routes must be refused **without state mutation**, even if source limits would not trip.
- Optional work may be skipped. Five required GRID-fed services still complete after 100 uninterrupted host ticks; extraction takes 50 ticks. Single-player solution; no two-person dependency. Generator stays optional and stowed.
- The existing host repair locks, supply rules, equipment, meter evidence, protection trip logic, and save schema are reused without modifying core code or C01–C03 rules.

## Validations and evidence ceiling

`content/contracts/c04_whole_block/` contains the eight complete JSON contract definitions plus a host-intent solution trace. `tests/integration/test_CTL1_C04_whole_block.gd` checks successful full completion, deliberately overloaded east sign branch, rejected dual routing, missed optional, repair definition and unchanged prior contract mission state shapes.

This phase is content-only. Neither a physical in-game C04 mission scene nor real Windows/controller/Steam/GPU/UX playability is certified. Because new rules files change ADR-018 global `rules_revision`, older incompatible checkpoints remain preserved and can be rejected; no migration or deletion is performed. Authoritative CI evidence remains pending until observed.
