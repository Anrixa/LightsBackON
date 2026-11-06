# QA97–QA100 — Read-only tablet snapshot schema hardening batch

Baseline `2555e02fcf7f364a9794674ece0239cdc29d5f6d` (QA96, CI successful).

| Phase | Scope | PR |
| --- | --- | --- |
| QA97 | Complete, unique ordered node IDs; embedded node IDs agree with stable catalog keys | #101 |
| QA98 | Typed node fields, declared status/findings, well-formed graph edges | #102 |
| QA99 | Typed and declared objective rows before Objectives tab creation | #103 |
| QA100 | Exactly two existing localization keys in nonempty optional district/contract header context | #104 |

Each phase has a dedicated evidence document and regression test in `tests/unit/test_V07_ui.gd`. Phase branches are cut sequentially from merged `main`, never stacked on unmerged work.

## Verification contract

- Exact PR-head `bash tools/run_tests.sh` Linux/Windows, with pinned standard Godot 4.7.2.
- Windows release export, source/build manifest check and headless smoke.
- QA51 resource-lifetime isolates on Linux and Windows.
- Post-merge `main` CI on the final exact merge commit; check GitHub Actions rather than infer a pass from this checkpoint document.
- Cross-check canonical grid/reference hashes and maintain preexisting golden results.

## Unverified / unchanged

- No simulation/power, host authority, networking, Steam integration, campaign save/reward, third-party assets or publishing changes.
- Physical Windows GPU/P95/memory and real controller checks (#51), UX01/V09 human usability runs, F02/F06 real two-PC Steam and external approvals remain pending.
- No promotion of the original 66-task blueprint statuses, no invented performance or work-hour measurements, and no release certification.

## Resume notes

Verify all four PR merges and final `main` SHA/CI conclusions. Future work must start from that exact main commit; do not count cloud checks as physical/Steam acceptance.
