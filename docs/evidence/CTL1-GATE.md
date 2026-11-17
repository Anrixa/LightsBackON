# CT-L1 Alder content-track gate — C02, C03, C04

- Date: 17 November 2026.
- Authority: ADR-017 parallel logic/data track; separate from canonical CT03 and D08 acceptance.
- Gate status: **PASS for Linux/Windows headless contract logic** after final exact-head CI, subject to final-head check; **HOLD for scene, controller, GPU, multiplayer and release qualifications**.
- Actual engineering hours: **not recorded**. Repository history is evidence of code changes, not a timesheet; no hours are inferred.

| Contract | Evidence | Observed solution | Scope ceiling |
| --- | --- | --- | --- |
| C02 Dinner Rush | [Original CTL1-C02](CTL1-C02.md), [CT-BP-C02 correction](CT-BP-C02.md), PR #165, [CI #44003254561](https://github.com/Anrixa/LightsBackON/actions/runs/44003254561) | Corrected SOLVED 395 ticks / 54 steps, 646/646 Linux+Windows tests | **SOURCE_ALIGNED_HEADLESS_CANDIDATE**; physical scene/HUD/human and release HOLD |
| C03 Roof Route | [CTL1-C03](CTL1-C03.md), PR #158, CI #43919744681 | 172 ticks, 27 steps in latest C04 CI | CLOUD_VERIFIED logic |
| C03 physical preview | [CTL1-C03-P01](CTL1-C03-P01.md), PR #159, CI #43928639759 | Fixed ladder transition headless | HEADLESS_VERIFIED, explicitly unsaved |
| C04 The Whole Block | [CTL1-C04](CTL1-C04.md), PR #160, [CI #43990072603](https://github.com/Anrixa/LightsBackON/actions/runs/43990072603) | 206 ticks, 65 steps | CLOUD_VERIFIED logic; physical scene absent |

The final C04 source verification had 593 Godot tests, 43,909 assertions and zero failures on **each** Linux and Windows runner, reference parity and exported Windows headless smoke; this is not multiplayer, performance or a player playthrough.

The C02 SIGN/2400-tick provisional design remains documented only as a historical record; corrected MARKET and PUB each require 100 continuous supply ticks by the 1800-tick opening deadline. C03/C04 original-sheet fidelity mismatches remain HOLD.

## Unclosed qualification gates

1. Actual C02 and C04 in-game scene/art/interactions, and C03 actual GUI/controller rooftop test; physical host range and visual feedback with people.
2. Target-class exported GPU P95/memory, 720p/1080p screenshots, 150% readability, accessibility and human pacing/UX.
3. Contract-scope rules-revision/save continuity. No user save migration, deletions or release promotion have been done.
4. Official `docs/backlog.json` CT03 is NOT_STARTED until D08. F02/F06 require two real Steam PCs on separate networks, and V09/D08 gates remain open.
5. The broader contract-content track continues with CT-L2 C05–C08 only as a **separate development phase** if owner direction permits.

## Gate decision

C02–C04 **headless authored contract development** is substantively implemented and tested; retain CLOUD_VERIFIED with the physical/release gates open. Final exact-head CI for this documentation update and PR merge must be verified before marking the gate's source-merge step done. Do not present cloud CI as release certification.
