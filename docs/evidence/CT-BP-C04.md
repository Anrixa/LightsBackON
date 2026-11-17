# CT-BP/C04 — correction development evidence

- Date: 17 November 2026.
- Branch: `task/CT-BP-C04-four-pu-sign-latch` from merged C03 main `7b1f39d4e5beb82a20dd66a5d3350a4d364a2d5e`.
- Authority: original development blueprint pp.18–20, correction tracker, `docs/design/CT-BP-C04-original-blueprint-spec.md`.
- Status: **IMPLEMENTED_PENDING_INDEPENDENT_CI**; this document is an engineering record, not a certification.
- Existing provisional CT-L1/C04 candidate, evidence and all prior contract data are preserved.

## Changed

- Corrected direct GRID sign feeder to capacity 4 PU, initially uninstalled/disabled, installed by isolated host-controlled `R_SIGN_SPUR` repair.
- Added a dedicated 100 consecutive tick GRID-sign optional supply latch, including same-tick dropout handling via existing host mission observer.
- Removed legacy immediate optional sign reward and rewired the objective to the latch. Required Alder 20 PU and optional 3 PU remain unchanged.
- Retained deliberately unsafe east 14/12 route and atomic dual-route refusal.
- Expanded C04 GDScript tests to source exactness, 99/100 threshold, switch and breaker drop/reset, rejected dual feed, unsafe feeder trip, optional omission, save/restore/forgery refusal, permanent cable stow exemption, malformed definitions, and prior contract state shapes.
- Updated the host-intent solution trace to assert both `latch` and `verified` on the same 100-tick supply interval.

## Evidence not yet claimed

- Exact final branch SHA and CI run results: **PENDING**.
- Full content validator + model reference parity + all C01–C08 solution replay: **PENDING CI**.
- Independent Linux and Windows: **PENDING CI**; do not count source edits as tested.
- Post-merge main CI: **PENDING**.
- Physical sign-route scene placement, real human/controller, 3D UX, Windows GPU targets, compatibility with deployed old saves, Steam F02/F06: **HOLD**.

## Resume notes

Do not merge until exact PR-head Linux and Windows checks pass. Diagnose and correct any test failure; preserve failed-run evidence. Then merge via PR, verify merged-main dual-OS checks, update tracker and PR/evidence status as verified. C05 is the next separate corrective phase. Do not silently promote the old provisional CT-L1/C04 spec to blueprint certification.
