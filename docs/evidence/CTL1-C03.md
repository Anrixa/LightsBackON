# CT-L1/C03 Roof Route — verified headless content development

- Date: 17 November 2026 (UTC CI log: 16 November 2026).
- Branch: `task/CTL1-C03-roof-route-logic`, created from main `4d71ca6c66bdf76852f25a91e631714cc2ba8013`.
- Implementation source head tested: `24801e7f5708c2028f38599b31d43ecfa9991d35`.
- GitHub pull request: [#158](https://github.com/Anrixa/LightsBackON/pull/158).
- **Status: CLOUD_VERIFIED (content and headless host logic only)**. This is not official CT03 completion or C03 Windows physical gameplay certification.
- Authority: ADR-017 independent content logic; official backlog CT03 retains D08 dependency.
- Contract specification: `docs/design/CT-L1-C03-contract-spec.md`.

## Implemented

Eight C03 definitions (grid, mission, meter, repairs, switches, equipment, tablet, solution) with original Alder 12 PU roof bypass vs overloaded west crossfeed, optional 1 PU beacon, required GRID supply verification and extraction. Host-only `use_ladder` intent grants a durable, idempotent access receipt, explicitly refuses unknown/out-of-range/payload-forged ladder actions and keeps rooftop splice locked before authorization. Existing C01 and C02 definition files and their durable mission-state shapes are unchanged. Seven targeted regression tests cover valid and unsafe routes, optional omission, forged receipts and legacy compatibility.

## Observed automated checks (first implementation CI)

- [CI #43919744681](https://github.com/Anrixa/LightsBackON/actions/runs/43919744681) — Linux **success** and Windows **success**, associated with PR #158 implementation head `24801e7f5708c2028f38599b31d43ecfa9991d35`. GitHub's PR merge test commit was `237920113f40a71b44abfa3303db65e62a2fae98` as shown by Windows QA57.
- **Linux Godot test suite:** 577 passed, 0 failed, 43,581 assertions.
- **Windows Godot test suite:** 577 passed, 0 failed, 43,581 assertions.
- **Actual host solution replay:** `SOLVED C03 in 172 ticks (27 steps)` on both OS runners. This is simulation time, **not** a measured human playthrough.
- **Reference parity:** 32 case runs (forward + reversed), 246 command hashes, 10 definition rejections; content hashes identical. Reference model is re-derived, not the original authored oracle.
- **Windows:** Godot 4.7.2 release EXE/PCK export, headless boot smoke and `QA57_EXPORT_PREFLIGHT=PASS`; tracked script UID check passed.
- Both OS jobs ended green. Godot logs include some known non-fatal `Node not inside tree` diagnostics during other existing tests and deliberate UI gate refusal messages; job-level success is not a claim of a warning-free engine log.
- CI validation includes JSON integer-content checks and all authored contract solution traces (C01, C02, C03). No Steam account/publishing, external paid asset or destructive operation was performed.

## Unverified and safety boundaries

- No in-game selectable C03 mission scene, rendered rooftop level, physical fixed ladder/landing transition, real 3D range/collision verification, physical player/controller or people acceptance, 720p/1080p C03 screenshots, GPU P95/memory or two-network Steam qualification.
- The trace's host range callback is a controlled logic fixture; it **does not prove** real player coordinates or safe roof traversal.
- New rules content changes the ADR-018 global rules revision. Older incompatible checkpoints remain preserved but may be rejected; no save migration/deletion or promotion was authorized.
- Official `docs/backlog.json` CT03 remains blocked on D08; F02/F06/V09 continue as separate gates.

## Resume

This evidence and its tracked status are a **documentation-only follow-up** to the passed implementation CI. Verify exact final PR-head CI again before merging; if green, merge PR #158 with a merge commit and record the final merge URL/status in a separate follow-up without claiming physical completion. Future C03 scene work must implement the host-approved ladder and landing geometry, selection/menu and range/collision checks, then collect real Windows/controller/GPU evidence.
