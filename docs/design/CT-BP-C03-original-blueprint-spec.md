# CT-BP/C03 — Roof Route original-blueprint corrective contract

**Date:** 17 November 2026. **Blueprint authority:** `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf` p.19, via the tracked reconciliation in `docs/design/CT-BLUEPRINT-CORRECTIONS.json`. **Scope:** host-authoritative source logic, JSON authoring, C03 unsaved preview messaging and headless tests. **Parent CT03 official backlog remains gated.**

## Corrected opening and electrical puzzle

- Original Alder `GRID` is 24 PU. `JW` starts with a failed/tripped fuse, rather than supplying west services immediately. The direct `E_GRID_JE` trunk remains damaged and unusable.
- Repair `R_JW_FUSE` with the existing meter-first, isolation, component replacement and restoration state machine. On the repaired west feeder, 9 PU of required west services plus 1 PU `LADDER_LIGHT` draw 10 of 12 PU.
- The fixed west ladder is host-authorized **only after 50 consecutive 10 Hz ticks (5 seconds) of valid GRID supply** at the access light. Both ladder endpoints require this durable latch. Unknown, out-of-range, early and forged client ladder actions are refused without a local teleport.
- The separate `E_GRID_ROOF` feeder is authored at 12 PU and initially disabled; the rooftop splice `R_ROOF_SPLICE` repairs damaged `E_ROOF_JE` only after the ladder receipt. `SW_ROOF_FEED` enables the alternate feeder through a host intent. East required load is 11 of 12 PU. The damaged direct east route is not silently repaired.
- The west crossfeed is unsafe: required east11 plus west9 and access1 exceeds the 12 PU west feeder and trips protection after 15 overloaded ticks. The safe solution uses the roof bypass. Total required GRID demand after restoration is 21 of 24 PU.
- `ROOF_BEACON` remains the stable visual/entity ID for compatibility with the unsaved preview, but is now the blueprint's **2 PU rooftop work light**. Its grid branch is removed: it instead uses the portable generator's `E_TEMP_ROOF_LIGHT` route. `GEN` is rated 6 PU.

## Optional award and extraction

- The 2 PU work light must be supplied from the valid **GEN source for 100 consecutive 10 Hz ticks (10 seconds)**. Supply loss, including an off/on pair between two grid ticks, resets an unfinished counter. Its completed latch survives later disconnection. A generator source that is overloaded, offline or misrouted never grants the reward.
- It is an **optional star objective only**, not a mission failure/deadline. Omission permits required restoration, 100 continuous verification ticks and 50-tick extraction, scoring 2 stars with no preventable trips; completion of the optional latch earns 3.
- The generator must be stopped, disconnected and returned to storage before extraction. C01, C02 and non-C03 optional results retain their prior field shapes.

## Host authority and save boundaries

- New `access_latches[].source` qualifies which source powers a latch; `fixed_ladders[].requires_latch` gates a physical ladder receipt; `optional_latch_rewards` awards only the specified completed bonus latch. All are conditional features, absent from earlier contract definitions and snapshots.
- C03 latch counters and ladder receipts are durable. Invalid latch names, missing counters, out-of-range progress, inconsistent granted progress and invented ladder IDs cause **fail-closed restoration without partial mutation**. This is format validation, not cryptographic anti-tamper or a released-save migration guarantee.
- The C03 preview remains explicitly **unsaved**, and its fixed ladder can still be tested in a controlled scene; this source repair does not certify in-game selectable roof-feed switching, generator socket visuals/affordances, real controller completion, Steam or shipped checkpoint continuity. Do not import older C03 checkpoints without a reviewed compatibility decision.

## Test protocol and acceptance

- Replay all 58 C03 host-intent steps, plus C01–C08 solutions. Exercise early ladder/refusal, exact 50 and 100-tick boundaries, same-tick interruption, wrong west crossfeed protection, missed optional bonus, source score attribution, save-forgery rejection, invalid definitions and unchanged earlier mission save shapes.
- Validate the C03 preview's refusal to teleport while host light access is missing; physical Windows/controller/human walkthroughs remain independent tests.
- Godot 4.7.2 standard, full Linux and Windows CI, reference parity, Windows export/smoke and content validation were observed on source head `1451efa0a5126b9f4a9170be99666858c2356237` at [run #44034573394](https://github.com/Anrixa/LightsBackON/actions/runs/44034573394). The documentation follow-up requires its own final-head CI before merging.
