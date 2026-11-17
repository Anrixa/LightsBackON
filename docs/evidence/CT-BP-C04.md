# CT-BP/C04 — correction development evidence

- Date: 17 November 2026.
- Branch: `task/CT-BP-C04-four-pu-sign-latch` from merged C03 main `7b1f39d4e5beb82a20dd66a5d3350a4d364a2d5e`.
- Authority: original development blueprint pp.18–20, correction tracker, `docs/design/CT-BP-C04-original-blueprint-spec.md`.
- Status: **SOURCE_ALIGNED_HEADLESS_CANDIDATE** after independent dual-OS source CI; this is not physical or release certification.
- Existing provisional CT-L1/C04 candidate, evidence and all prior contract data are preserved.

## Changed

- Corrected direct GRID sign feeder to capacity 4 PU, initially uninstalled/disabled, installed by isolated host-controlled `R_SIGN_SPUR` repair.
- Added a dedicated 100 consecutive tick GRID-sign optional supply latch, including same-tick dropout handling via existing host mission observer.
- Removed legacy immediate optional sign reward and rewired the objective to the latch. Required Alder 20 PU and optional 3 PU remain unchanged.
- Retained deliberately unsafe east 14/12 route and atomic dual-route refusal.
- Expanded C04 GDScript tests to source exactness, 99/100 threshold, switch and breaker drop/reset, rejected dual feed, unsafe feeder trip, optional omission, save/restore/forgery refusal, permanent cable stow exemption, malformed definitions, and prior contract state shapes.
- Updated the host-intent solution trace to assert both `latch` and `verified` on the same 100-tick supply interval.

## Independently verified source run

- Implementation source SHA: `96a30e1cd26e299551b9ec05a0db96eb9599ea5e` ([commit](https://github.com/Anrixa/LightsBackON/commit/96a30e1cd26e299551b9ec05a0db96eb9599ea5e)).
- Independent exact-source [CI #44041360152](https://github.com/Anrixa/LightsBackON/actions/runs/44041360152): **Linux SUCCESS; Windows SUCCESS**.
- Each operating system: **657 tests passed, 0 failed, 47,656 assertions**; content **85 JSON / 0 errors**, contrast **44 checks / 0 failures**.
- C01–C08 full solution replays all SOLVED. C04 **206 host ticks / 65 steps**.
- Python reference/model parity **MATCH**: 32 case runs, 246 command hashes, 10 malformed-definition rejections.
- Windows pinned Godot 4.7.2 export, exported EXE/PCK headless launch/source-pin preflight and QA57 tracked UIDs **PASS**. Runner has no target GPU, Steam two-network hardware, human/controller evidence.
- Earlier [CI #44041039477](https://github.com/Anrixa/LightsBackON/actions/runs/44041039477) is preserved: Linux 656 passed/1 failed because the optional-omission negative test incorrectly expected a sign latch even when intentionally skipping sign work. The host solution and other 13 C04 tests passed. Corrected test expectation in `96a30e1`; subsequent full dual-OS run green.
- Following this documentation/tracker receipt commit, require another exact-final-head dual-OS CI before merging.

## Evidence not yet claimed

- Exact final documentation branch-head CI and merged-main CI: **PENDING**.
- Content validator, model reference parity and C01–C08 solution replay: **PASS on implementation source SHA**; final-head revalidation pending.
- Independent Linux/Windows: **PASS at implementation source SHA**; final documentation commit needs exact-head CI.
- Post-merge main CI: **PENDING**.
- Physical sign-route scene placement, real human/controller, 3D UX, Windows GPU targets, compatibility with deployed old saves, Steam F02/F06: **HOLD**.

## Resume notes

Do not merge until exact PR-head Linux and Windows checks pass. Diagnose and correct any test failure; preserve failed-run evidence. Then merge via PR, verify merged-main dual-OS checks, update tracker and PR/evidence status as verified. C05 is the next separate corrective phase. Do not silently promote the old provisional CT-L1/C04 spec to blueprint certification.
