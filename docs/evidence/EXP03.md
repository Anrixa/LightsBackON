# EXP03 — Host-authoritative 200-level dispatch task runtime

**Baseline:** EXP02 merged main `22fa6c5c7d5762b2ebd2c2b3905db564476bb6b2`. This record is a source engineering checklist, not CI proof.

## Implemented code boundary

- `expedition_contract_factory.gd` translates each original EXP01/EXP02 source-pinned level and its five task locations into real `PowerGrid`, `MeterModel`, `InteractionService`, `EquipmentService`, `SessionHost` and `MissionDirector` definitions. Existing C01–C12 remain untouched.
- Each candidate has three mandatory consumers, two feeder routes, the original meter-first eight-step, lock-protected west repair, optional separate GRID sign feed, and an intentionally overloaded west sign shortcut. Generated PU capacities are taken directly from EXP02's numerical plan and enforced by the real grid.
- `expedition_host_session.gd` is a new isolated run. The existing production `SessionHost.receive(peer, bytes)` validates sender, session, sequence, dedupe, rate, entity/position and tools. Host movement supplies positions; clients cannot report completed tasks, elapsed ticks, grid supply or rewards. Real `MissionDirector` requires continuous GRID supply for the authored 80–150 tick window and 50 extraction ticks. A task completes only when a genuinely accepted meter inspection, host grid switch, restored repair, optional evidence inspection or mission result proves its condition.
- `test_EXP03_runtime.gd` uses actual binary host command envelopes, actual repair tools and source level IDs, with all 200 candidate levels intended for full mission replays and all 1,000 task ID bindings. Tests also cover forged peers, replayed sequence, remote/unknown targets, meter-first, bad work order, overloaded shortcut and optional omission.

## Stage wiring (added in this batch)

- `scenes/expeditions/mission_stage.tscn` + `expedition_mission_stage.gd` instantiate one authored graybox, the existing physically colliding first-person character, noncolliding host-target plates, an actual physics line-of-sight callback, the host 10 Hz tick loop and a task-status overlay. All E/1–5 interactions are routed as encoded F03 commands; staff repair tool order remains validated by the original Interaction service.
- The dispatch atlas provides an **explicit experimental launch** action, validated again in `MainMenu` and at the scene boundary. The original atlas preview remains read-only until the player opts in. The stage deliberately keeps no saved progression, receipts or reward credits and returns to the existing menu on exit.
- Scene assertions are added in `test_EXP03_stage.gd`; successfully building a character and binding real collision rays is NOT evidence of a continuously walked or controller-tested route.

## Certification and compatibility

The existing atlas retains `DESIGN_BRIEFING_ONLY` and its 200 grayboxes retain `SCHEMATIC_NOT_PLAYABLE` until their actual production runtime scene, player/controller controls, physics sight/capsule path, UX and hardware tests qualify. The EXP03 headless range callback requires a **host-owned position provider**, not an untrusted client position; a physical scene may additionally provide a true physics collision/LoS callback. Staged test positions are NOT walked routes.

EXP03 provides **no** source-authorized pickups, personal field points/credits, durable expedition checkpoints, Steam sessions, campaign promotion or save migration. EXP04 will implement collectible/points authority, EXP05 progression; current C01 production persistence and twelve original contracts are unchanged. The data bridge is isolated outside `content/`, so the legacy C01 rules revision is not modified.

## CI / merge gates

- [ ] Exact *updated* final-head Linux and Windows full Godot suites, including stage integration, and source validation.
- [ ] 200 authentic host solution traces, all existing 12-contract replays, Python reference parity.
- [ ] Windows QA57 UID gate and EXE/PCK export/headless smoke.
- [ ] Independent merged-main Linux/Windows CI, with the exact SHA linked.
- [ ] Physical movement/line of sight/controller/target GPU/Steam/network/release: **OWNER HOLD**.

## Resume notes

After passing the source-only phase and the experimental scene integration, continue hardening real worksite collision/route clearance and player UX; EXP04 will implement collectible/point receipts. No physical playability tests have been run. Do not equate successful headless source replay with human/controller playability certification.
