> **Historical provisional C03 design (17 November 2026).** The original 1 PU beacon and missing 5-second ladder-light latch below describe the superseded source. For original-blueprint alignment and the verified corrective implementation, use [CT-BP/C03 source specification](CT-BP-C03-original-blueprint-spec.md) and [CT-BP/C03 evidence](../evidence/CT-BP-C03.md). The earlier CI and design history remain valid only for their original commit.

# CT-L1 / C03 — Roof Route

17 November 2026. ADR-017 authorizes independent **logic and data**, not official backlog CT03 qualification.

## Authoritative contract

A storm-damaged direct GRID-to-JE feeder strands the east three services. West homes and market already consume 9 PU. An available west crossfeed would carry 20 PU through the 12 PU upstream west feeder, tripping the protected branch after 15 continuous 10 Hz ticks. The correct route repairs GRID→ROOF→JE: required east load 11 PU, optional roof beacon 1 PU, total 12 PU, exactly the healthy feeder capacity. The 3 PU old sign remains disabled/excluded. All five GRID-supplied services are verified for 100 continuous ticks; the crew then extracts in 50 ticks. No optional service or timer is a hard fail.

The fixed ladder `LADDER_WEST` is an authored host-ranged command `use_ladder`, empty payload, first-use receipt, repeat-safe and checkpoint durable. It grants `ROOF_REACHED`, which gates the full meter-first rooftop splice state machine. A forged grant, unknown ladder, out-of-range action or invalid persisted receipt is refused. C01/C02 retain their pre-existing mission state shapes.

**Scope boundary:** No actual rooftop scene, ladder mesh, landing transition, controller animation, collision or physical host range integration has been implemented here. The tested host range callback is simulated by the solution runner, which is not physical proof. These remain explicit scene/UX gates. PU numbers are game rules, not electric engineering.

Eight authored JSON definitions and a full host-intent solution are validated by normal contract replay. Negative tests cover overload and breaker recovery, optional omission, repeated ladder action, forged payload/save and C01/C02 regression. Results and limitations live in `docs/evidence/CTL1-C03.md`.

Adding C03 content changes the global rules revision under ADR-018; existing incompatible offline checkpoints are preserved and may be rejected, not migrated or deleted. Do not claim CT03 completion, Steam multiplayer, GPU P95 or production readiness until those independent gates actually pass.
