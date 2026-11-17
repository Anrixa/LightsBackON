# CT-L3/C10 — Community Night original-sheet source implementation

- Source authority: original Development Blueprint v1.0 pp.18 and 20–21, and `docs/design/CTL3-C10-C12-blueprint-spec.md`.
- Branch `task/CT-L3-C10-community-night` created from C09 merged main `13223b7472a9720a8e2630a497ee02452fb407e0` (post-merge CI #44138557595 SUCCESS).
- **Current status: SOURCE_IMPLEMENTED_CI_PENDING.** No unobserved CI or physical certification claims.

## Authored source
- Hill Road GRID28, WEST/EAST 14 each, GEN6, six required services25 PU. WEST fuse initially failed/tripped, EAST healthy.
- STAGE3 is optional and must never overload WEST feeder (13+3=16 > 14). A separately isolated and installed GRID→STAGE_SPUR feeder4 carries the 3 PU bonus, bringing grid supply to exactly 28/28.
- The host-only `optional_timed_latch` starts at first mission simulation tick, requires STAGE supplied from GRID for 100 consecutive ticks and **latch completion by tick 2400** (40-second event clock). Completing at tick 2400 qualifies, 2401 does not. Bonus failure does not block repairs, final 100-tick grid verification, extraction or the other two stars.
- Strict conditional saved timer fields; older contracts C01–C09 preserve their previous durable shapes. Headless equipment remains stowed; no automatic data migration/deletion.
- A host-intent solution trace, source tests and negative overload/dual-source routes are part of the pending validation.

## Mandatory gates
- Exact-head Linux/Windows full Godot suite, C01–C10 replay, Python parity/content validation and Windows QA57 build/export/smoke; source-only final PR CI and merged-main CI before promotion.
- Real Hill Road world stage, sockets and 3D cable, performance, real controller/human and event sound/lighting, historic-save continuity, real two-network Steam F02/F06 and canonical CT06 **HOLD**. The stage UI receives only host state.
