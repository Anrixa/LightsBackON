# CT-L1/C04 — The Whole Block: verified headless contract evidence

- Date: 17 November 2026 (CI 17 November 2026 UTC).
- Branch: `task/CTL1-C04-whole-block-logic`; base `main` `d8de4050592c4db3893c60e83e05188b19a4220a`.
- Implementation head tested: [`1a9cfde193f5d024d080907e6296b61372fc74ea`](https://github.com/Anrixa/LightsBackON/commit/1a9cfde193f5d024d080907e6296b61372fc74ea).
- Pull request: [#160](https://github.com/Anrixa/LightsBackON/pull/160).
- Verification: [CI #43990072603](https://github.com/Anrixa/LightsBackON/actions/runs/43990072603), Linux **success**, Windows **success**.
- **Status: CLOUD_VERIFIED for content, simulation and headless host integration only**; not a playable/physical C04 or official CT03 completion.

## Implementation

- Eight original C04 JSON files: grid, mission, repairs, equipment, switches, meter, tablet, solution. The contract is called **The Whole Block**.
- Two required faults: failed/tripped JW west fuse and damaged 12 PU JE feeder; direct independent 3 PU sign spur through a separate SPUR junction is optional. The sign's east route is normally isolated at EAST_SIGN. Total GRID draw with optional sign is 20 + 3 = 23/24 PU.
- Meter-first, host-locked normal repair steps cover the two required faults and the optional sign splice. The generator is available but remains stowed in the known-valid route. A wrong choice to open the east sign isolator draws 14/12 PU on JE and trips after 15 ticks; two energized incoming routes to the sign are refused before grid mutation.
- Standalone localization, stable authored tablet nodes, seven integration tests and a 65-step host-intent solution. All C01–C03 contract files remain unchanged. Canonical `docs/backlog.json` CT03 remains NOT_STARTED behind D08.

## Directly observed checks

- **Linux:** 593 Godot tests passed, 0 failed, 43,909 assertions; `ALL CHECKS PASSED`.
- **Windows:** 593 Godot tests passed, 0 failed, 43,909 assertions; `ALL CHECKS PASSED`; pinned 4.7.2 Windows release export and headless smoke completed, `QA57_TRACKED_GODOT_UIDS=PASS`, `QA57_EXPORT_PREFLIGHT=PASS`.
- **Contract solution replays on both platforms:** C01 SOLVED in 316 ticks / 56 steps; C02 188 / 44; C03 172 / 27; **C04 206 / 65**. These are host simulation ticks, not human completion duration.
- **Reference parity:** MATCH on 32 case runs, 246 command hashes, 10 malformed definition rejections; content hash identical to the independently re-derived Python model.
- **Content:** 53 JSON files validated, zero errors. UI contrast checks: 44, zero failures.
- New regression tests specifically cover safe 23/24 PU completion with three stars, 15 tick unsafe east branch, atomic rejection of dual sign feeds, two-star optional omission, stable prior mission checkpoints and authored repair data.
- The first full run #43989704037 ran 592/593 tests, with one test-only assertion comparing Godot's JSON-decoded `2.0` float to integer `2`; corrected to an explicit integer comparison in `1a9cfde193f5d024d080907e6296b61372fc74ea`. The full successful #43990072603 run repeated **all** checks on both OS runners. Earlier #43989511507 was cancelled by an intentional branch revision.

## No physical or release certification

C04 has no selectable in-game scene or real player path, no C04 Windows GUI/controller/human sessions, no target GPU P95/memory/screenshots, no second-network Steam evidence, and no official D08/CT03 promotion. The authored direct sign spur's real 3D marker/cable visuals remain future work. C03's optional ladder preview remains unsaved and separately gated.

Adding C04 rules changes the ADR-018 global rules revision. Older incompatible C01–C03 checkpoints are **preserved and explicitly refused**, not migrated/deleted. Compatibility across contract additions is a separate future design/qualification step before promotion.

## Resume notes

After this documentation/tracker update, require final **exact PR-head** Linux/Windows CI success. Merge PR #160 with a merge commit only when both pass, and record the merge commit in the PR discussion. The CT-L1 content *development* milestone is then complete at CLOUD_VERIFIED; do not claim official CT03, production content, C04 scene playability, D08, F02/F06 or Steam qualification. The CT-L1 gate report lists all unverified items.
