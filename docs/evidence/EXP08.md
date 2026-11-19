# EXP08 — Dynamic Fault Diagnosis and Alternative Restoration

Branch: task/EXP08-dynamic-fault-diagnostics. Based on EXP07 draft PR #192, itself stacked on EXP06 draft PR #191.

EXP008 is an additive host-authoritative mechanical layer for 200 experimental levels. Its two diagnostic probes per level reveal separate live host observations. A source-defined fault console permits two genuinely different electrical operating paths: isolation needs the real SPUR circuit OFF; rerouting needs SPUR ON, consumes a finite backup relay, and requires a longer stable hold. Each path requires host-inspected WEST, restored repair, energized EAST, completion of EXP07 devices and a safe EXP06 hazard phase.

After operating the console, the real SessionHost clock advances a bounded stabilization hold; supply or safety interruptions trip a recoverable fault, and a new host-authorized reset plus fresh preparation are required. Reroute spares are not replenished. No wire payload includes a client tick, position, reading, graph, result or points. Original SessionHost membership, session, sequence, dedupe, rate, range and optional physics LoS remain mandatory.

Implementation:
- 200 level/source-key-bound profiles, eight domain-specific fault classes, 400 probes and 200 control consoles
- source audit, independent Python mutation suite, 200×2 Godot reference replay, host-envelope/extraction tests
- opt-in first-person console and R route choice, source-only HUD, both Windows export presets and standard test runner
- canonical host snapshots, revision increments and state hashes include EXP08 and host fixed ticks
- original C01–C12 save/credits/contract rules and EXP04 personal field-point ledger are unchanged

Acceptance gates: verify all 200 source profile identities and both solutions; tamper and failure/recovery tests; EXP01–EXP07 and original contracts full Linux/Windows CI; exact-head QA57 Windows export/smoke; independent merged-main regression. EXP06 and EXP07 must pass their own gates before integration.

HOLD: human/controller continuous traversal; collision/route certification; real GPU/Steam/network tests; art signoff; production saves/migrations/release; economy/reward promotion. This is one tested fault-state framework over 200 authored profiles, NOT 200 independently invented puzzle engines.
