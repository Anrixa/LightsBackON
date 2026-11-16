# CT-L1/C02 — Dinner Rush, logic/data phase

- Date: 17 November 2026; starting `main` `f0be6688ff0bd7744098eed215e17053c2474876`.
- Branch: `task/CTL1-C02-dinner-rush-logic`.
- Status: **IN_PROGRESS — authored code/data/regression package; CI not claimed before it runs.**
- Authorization: ADR-017 decision 3 (C02-C12 content logic allowed while F02 blocked), DS07 CT-L1.
- Design/acceptance contract: `docs/design/CT-L1-C02-contract-spec.md`.

## Implementation staged

Eight C02 definitions (grid, meter, equipment, repairs, switches, tablet, mission and host-intent solution). Two faults, optional 3 PU venue sign, timed optional opening bonus (four-minute 2,400 tick cutoff), five required grid services, zero extra mandatory tasks, and completed authoritative route trace. Existing C01 data and saved-state schema are not altered. Optional deadline is opt-in and persists only validated authoritative first-supply ticks.

Seven new DS/CT integration regressions test source/repair composition, full solution, late optional not blocking completion, unsafe dual supply refusal without state mutation, invalid deadlines, durable progress with tamper refusal, and C01 checkpoint shape preservation.

## Verification

- Linux/Windows `bash tools/run_tests.sh`, solution trace for every `content/contracts/*/solution.json`, Python parity, Windows export/headless smoke/QA57 and QA51 resource probe: **pending first significant-batch CI**.
- Real Windows player-selection/UI, scene integration, 720p/1080p controller run, measured human deadline pacing, rendered contrast/P95 and owner acceptance: **not performed**.
- Real second-account Steam F02/F06 and V09 study remain HOLD; canonical CT03 remains NOT_STARTED behind D08.

## Resume

If CI finds an error, keep work on this one branch, fix and rerun exact-head CI. Do not merge failing source. After verified merge, update the evidence/status as a new docs checkpoint. C03 is the next proposed separate authoring phase.
