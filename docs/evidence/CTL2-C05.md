# CT-L2 / C05 — Canal Yard Pump Access: verified host-logic candidate

- Date: 17 November 2026 (GitHub Actions timestamps 2026-11-17 UTC).
- Branch: `task/CTL2-C05-canal-pump-access`; parent `main` `71b9b6e05de94eac9daf1318dcd26230e1627295`.
- Source head tested: [`939c01ffa4ebff72939cbf0d16475073129d66ed`](https://github.com/Anrixa/LightsBackON/commit/939c01ffa4ebff72939cbf0d16475073129d66ed).
- Pull request: [#161](https://github.com/Anrixa/LightsBackON/pull/161).
- Full Linux/Windows CI: [#43992204512](https://github.com/Anrixa/LightsBackON/actions/runs/43992204512) — both jobs SUCCESS.
- **Status: CLOUD_VERIFIED for original provisional host-authoritative logic/data only**. Not a verified original-blueprint C05 spec, playable 3D Canal Yard or canonical CT04 completion.

## Implemented content

Eight C05 data files in `content/contracts/c05_canal_pump_access/` (grid, mission, equipment, meter, repairs, switches, tablet and a 62-step host-intent solution). New CT-L2 tracker and contract specification, English localization and nine regression tests.

Gameplay candidate: 24 PU GRID and 6 PU portable GEN, dock 8 PU + cold-yard 11 PU required loads, optional 2 PU dock beacon on the 12 PU dock feeder. Independent 4 PU temporary pump loads require 80 and 100 continuous ticks, respectively, to grant two separately latched repair access rights. Running both pumps concurrently draws 8/6 PU and trips TEMP protection after 15 ticks. Staged single-generator operation avoids the overload and permits both repairs; optional beacon does not block 2-star core completion.

## Observed CI acceptance

- **Linux:** 602 Godot tests passed, **0 failed**, 43,996 assertions. Full pipeline: `ALL CHECKS PASSED`.
- **Windows:** 602 Godot tests passed, **0 failed**, 43,996 assertions. Full pipeline: `ALL CHECKS PASSED`, Windows Godot 4.7.2 EXE/PCK release export and headless launch, `QA57_TRACKED_GODOT_UIDS=PASS` and `QA57_EXPORT_PREFLIGHT=PASS`.
- 61 content JSON files validated; 0 content errors.
- Exact known host-intent solution replays on each OS: C01 SOLVED in 316 ticks / 56 steps, C02 188 / 44, C03 172 / 27, C04 206 / 65, **C05 382 / 62**. Ticks are simulation time, not human playthrough duration.
- Reference parity: MATCH across 32 cases (forward and reversed), 246 command hashes, 10 malformed definition rejections, identical content hashes (reference model independently re-derived).
- Nine new tests include independent access latch thresholds, required 5/5 and optional 3-star solution, 15-tick generator overload followed by recovery, interrupted drain counter reset, 2-star omitted optional, strict durable state rejection, invalid latch schemas, and legacy C01-C04 checkpoint-shape compatibility.

## Unverified and explicit limits

- **Primary blueprint C05 contract sheet was not accessible** to this GitHub-connected work environment (the repo contains a PDF, but no text extraction/screenshot access succeeded). Names and numbers in `CT-L2-C05-contract-spec.md` are newly authored provisional design values; compare them against original blueprint pp. 18–21 before official content promotion. Do not infer these were prescribed by the original C05 sheet.
- No physical Canal Yard scene, model, colliders, water-height scalar presentation, player movement/ranged panel access, in-game contract selection, rendered screenshots, human keyboard/controller trial, audio/UX evaluation or target GPU P95/memory qualification.
- This content addition changes global ADR-018 `rules_revision`. Older incompatible checkpoints are preserved but may be rejected, never silently migrated or deleted.
- F02/F06 real Steam multiplayer qualification, CT01/CT03 dependencies, canonical CT04, and official release gates are untouched.
- This documentation/track status update itself needs one **final exact PR-head CI** before merging. Do not mistake this earlier CI for source revision tested after the evidence commit.

## Resume / next phase

Verify final exact-head Linux + Windows full CI; fix if required. Merge PR #161 with merge commit only when exact final head passes and document the SHA in PR discussion. Continue in a fresh phase with CT-L2/C06 cold-chain optional grace timer after verifying source design; do not set CT04 to DONE.
