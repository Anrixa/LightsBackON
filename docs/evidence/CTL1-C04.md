# CT-L1/C04 — The Whole Block, implementation evidence

- Date: 17 November 2026.
- Branch: `task/CTL1-C04-whole-block-logic` based on main `d8de4050592c4db3893c60e83e05188b19a4220a`.
- Authority: ADR-017 C02-C12 independent content logic; official backlog CT03 remains NOT_STARTED (D08).
- Scope: eight contract rule/solution JSON files: grid, mission, repairs, switches, equipment, meter, tablet, solution. No playable scene or external assets.
- Stage: **IMPLEMENTED_UNVERIFIED — awaiting exact-head GitHub Linux/Windows CI**.

## Implemented

Two required fault repairs; independent 3 PU optional direct sign spur; disabled east-sign crossfeed; host-validated 15 tick overload and dual-supply refusal; verified mission completion and optional 3-star reward; standalone localization and tablet content. C01–C03 contract files are unchanged.

## Verification checklist

- [ ] Linux `bash tools/run_tests.sh` and Godot 4.7.2 solution replay C01–C04
- [ ] Windows `bash tools/run_tests.sh`, export, headless boot and QA57
- [ ] Reference model parity, JSON rules validation, localization closure
- [ ] Targeted wrong-route and skipped-optional tests
- [ ] Post-documentation exact-head CI and optional QA51 resource probe

No test results are claimed before the actual GitHub run succeeds.

## Open gates

Actual C04 physical scene, keyboard/controller/human route, GPU P95/memory, official D08/CT03 status, F02/F06 cross-network Steam, and contract-scoped checkpoint compatibility. No user files or saves were deleted or migrated.

## Resume notes

Complete the GitHub checks on this branch. If tests fail, fix and repeat exact-head checks. Only when green, update the evidence/tracker to `CLOUD_VERIFIED`, verify the resulting final head, merge via PR; do not set canonical CT03 to DONE.
