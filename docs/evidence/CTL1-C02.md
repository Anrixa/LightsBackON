# CT-L1/C02 — Dinner Rush, logic/data phase

- Date: 17 November 2026; starting `main` `f0be6688ff0bd7744098eed215e17053c2474876`.
- Branch: `task/CTL1-C02-dinner-rush-logic`.
- Status: **CLOUD_VERIFIED for content logic only.** Merged through [PR #156](https://github.com/Anrixa/LightsBackON/pull/156) into `main` at `395e60303904f1014bebe254607c8a6f83f6afd5` after Linux/Windows full CI passed. C02 is not selectable/playable or officially CT03-qualified.
- Authorization: ADR-017 decision 3 (C02-C12 content logic allowed while F02 blocked), DS07 CT-L1.
- Design/acceptance contract: `docs/design/CT-L1-C02-contract-spec.md`.

## Implementation staged

Eight C02 definitions (grid, meter, equipment, repairs, switches, tablet, mission and host-intent solution). Two faults, optional 3 PU venue sign, timed optional opening bonus (four-minute 2,400 tick cutoff), five required grid services, zero extra mandatory tasks, and completed authoritative route trace. Existing C01 data and saved-state schema are not altered. Optional deadline is opt-in and persists only validated authoritative first-supply ticks.

Seven new DS/CT integration regressions test source/repair composition, full solution, late optional not blocking completion, unsafe dual supply refusal without state mutation, invalid deadlines, durable progress with tamper refusal, and C01 checkpoint shape preservation.

## Verified substantial-batch automated acceptance

- First CI [#43911253578](https://github.com/Anrixa/LightsBackON/actions/runs/43911253578): **FAILED** (565 passed, five test failures). Four were caused by an obsolete C01-only early `NO_ACCESS` expect line in the copied east-repair trace; C02 deliberately has no pump access gate. One used an int/float equality check on the JSON-parsed deadline. These were test/trace defects, not claimed successes.
- Final exact source: `4c89661bdb7c90dee5730ae018b2ef515b8ec40b`; [Linux and Windows CI #43911687483](https://github.com/Anrixa/LightsBackON/actions/runs/43911687483): **SUCCESS on both platforms**, each **570 tests / zero failures / 43,123 assertions**. All seven C02 tests pass.
- Every `content/contracts/*/solution.json` is replayed by the normal test runner, not a mock completion flag: `SOLVED C01 in 316 ticks (56 steps)`; **`SOLVED C02 in 188 ticks (44 steps)`**.
- Reference parity: `MATCH: 32 case runs (fwd+rev), 246 command hashes, 10 definition rejections`, identical content hash. All content/int PU validation and Python tests pass.
- Windows Godot 4.7.2 release export, EXE/PCK headless launch, QA57 tracked UID check and `QA57_EXPORT_PREFLIGHT=PASS` at the same verified source head.
- **QA51 resource probe not run for this PR:** dedicated workflow paths only cover designated UI/scene/resource scripts, not C02's content or `scripts/simulation/mission_director.gd`; no resource-lifetime claim made. No Steam or paid action occurred.
- Merge commit for implementation: `395e60303904f1014bebe254607c8a6f83f6afd5`. Source tree keeps C01 original content definitions byte-identical, and new deadline fields are opt-in for C02 only.

## Not verified / acceptance boundaries

- No real C02 gameplay session in the Windows GUI, no selectable mission-root C02 scene, visual/UX/lighting acceptance, timing playtest, 720p/1080p capture, physical controller or actual target GPU P95/memory.
- New C02 rules files under `content/` change global rules-revision eligibility. Previous incompatible C01 checkpoints stay preserved and are rejected explicitly; **not migrated/deleted**. Cross-version continuity requires a separately approved and tested compatibility strategy.
- C03/C04 not started. Canonical `docs/backlog.json` CT03 remains NOT_STARTED due to its D08 dependency; F02/F06/V09 remain blocked/held.
- This is **code/data qualification, not CT03, C02 ship readiness, or release certification**.

## Resume

C02 is merged through PR #156 (implementation commit `395e60303904f1014bebe254607c8a6f83f6afd5`). Preserve original C01 definitions and mandatory workflow gating. This evidence PR records passed CI and explicitly unresolved in-game acceptance. The next separate, ADR-017-authorized phase is CT-L1/C03 Roof Route (fixed ladder access and bypass feeder logic/data). Never promote official CT03 until D08 is cleared.
