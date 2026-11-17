# CT-L2 Canal Yard development-track gate — C05–C08

- Date: 17 November 2026.
- Authority: ADR-017 independent content/logic track, original Development Blueprint v1.0 pp.18–21.
- Development scope: C05, C06, C07, C08. Canonical `docs/backlog.json` CT04/CT05 milestones are separate and are not promoted by CT-L2.
- Gate status: **PASS for headless C05–C08 implementation and automated Linux/Windows solution replay; HOLD for C05/C06 original blueprint fidelity, all physical scene/hardware/multiplayer/release acceptance**.
- Actual engineering hours and costs: **not logged or inferred from GitHub history**.

| Contract | Last verified phase | Contract replay | Original-blueprint sheet fidelity | Remaining mandatory action |
| --- | --- | --- | --- | --- |
| C05 provisional Pump Access | [PR #161](https://github.com/Anrixa/LightsBackON/pull/161); [evidence](CTL2-C05.md) | SOLVED 382 ticks / 62 steps in C08 CI | **HOLD_CONFIRMED_MISMATCH** — wrong Canal topology/loads/pump durations/optional clock | Replace provisional content with blueprint C05 Rising Water; 5/4 PU pumps, 120 ticks each, first-equipment-pickup 180 s cold-store bonus |
| C06 provisional Cold-Chain Window | [PR #162](https://github.com/Anrixa/LightsBackON/pull/162); [evidence](CTL2-C06.md) | SOLVED 382 ticks / 62 steps in C08 CI | **HOLD_CONFIRMED_MISMATCH** — wrong Canal topology/loads/timer semantics | Replace provisional content with blueprint C06 Cold Chain; 4 PU pump 120 ticks, exclusive cold-store routes, cumulative outage strictly below 120 s |
| C07 Wrong Label | [PR #163](https://github.com/Anrixa/LightsBackON/pull/163); [evidence](CTL2-C07.md) | SOLVED 169 ticks / 25 steps in C08 CI | SOURCE_ALIGNED_HEADLESS_CANDIDATE | In-world panel plate, meter, controller/human and exported GPU evidence |
| C08 Split Supply | [PR #164](https://github.com/Anrixa/LightsBackON/pull/164); [evidence](CTL2-C08.md) | SOLVED 277 ticks / 35 steps in [CI #43999774167](https://github.com/Anrixa/LightsBackON/actions/runs/43999774167) | SOURCE_ALIGNED_HEADLESS_CANDIDATE | In-world dual-source cabinet, source transition UX, physical controller and target GPU verification |

## Cross-track blueprint reconciliation

The original primary blueprint was recovered and read on 17 November 2026. It also proves C02–C04 original-sheet mismatches; their earlier cloud headless tests **do not** certify fidelity:

- C02: MARKET and PUB, individually supplied continuously for 10 seconds before the briefing-relative 180-second deadline; exclusive portable generator routes.
- C03: 5-second west-fed access-light latch for fixed ladder and separate optional 2 PU roof work light for 10 seconds.
- C04: a 4 PU GRID-to-SIGN spur and 10-second optional sign latch, exclusive of the JE-to-SIGN route.
- C05: original Canal GRID30 / 14-PU west/east / GEN8 / loads13+12; 5 and 4 PU pump access for 120 ticks each and 180-second deadline measured from first equipment pickup.
- C06: original Canal topology, one 4 PU pump for 120 ticks, cold-store5, exclusive GEN/grid supply, and cumulative unsupplied cold-store time strictly less than 120 seconds.

Detailed acceptance criteria and negative tests are machine-tracked in [CT-BLUEPRINT-CORRECTIONS.json](../design/CT-BLUEPRINT-CORRECTIONS.json), all **NOT_STARTED**. No rewrites or promotions of historical provisional content occurred within C08. Each corrective contract must receive a separate code PR, observed host trace, falsification tests and exact-head CI before even source-aligned status is considered.

## Host and platform test receipts

- C08 implementation source `7af2e943a06017d7f50df93cd7981b7129d577ef` — [Linux/Windows CI #43999774167](https://github.com/Anrixa/LightsBackON/actions/runs/43999774167), **both SUCCESS**.
- Godot: **637 PASS, 0 FAIL, 45,948 assertions per platform**; content 85 JSON files/0 errors; C01–C08 host solution replays all SOLVED.
- Python reference parity: **MATCH** 32 case runs, 246 command hashes, 10 definition-rejection checks.
- Windows QA57 tracked GDScript UID sidecars, release EXE/PCK export, headless boot smoke and manifest/source-pin verification: **PASS**.
- CI #43999444015 was **FAIL** and remains auditable; the host initially restricted switches to nodes. The validated correction allows only host-authorized settable edge fields and adds depot same-tick interruption checks.
- The final documentation+gate PR source must pass its own Linux/Windows CI prior to merge. Merge-main CI must be checked afterwards; no gate is inferred from a pending job.

## Gates explicitly not passed

1. Actual 3D Canal Yard scene geometry and source tie/cabinet reachability, keyboard/controller real-world input checks, and independent human/UX playthrough.
2. Exported target-class GPU frame P95, memory, resolution/accessibility captures, or actual native Windows graphical run.
3. Real historical saved-session compatibility across release content revisions; no user save migrations, deletions or silent revisions were performed.
4. Steam F02/F06 two PCs on separate networks; V09/D08 human/design acceptance, and official CT04/CT05 critical-path qualifications.

## Gate decision

CT-L2 **headless source-logic development is complete for C05–C08** when PR #164 is exact-head CI verified and merged, while C05/C06 original-sheet certification remains **HOLD** and full CT-L2 production/physical completion remains **HOLD**. The next corrective development milestone should start with C02 and proceed through C06, each independently reviewable; never promote the provisional C02–C06 despite historical cloud pass reports. No Steam account or publishing is required for these corrective engineering steps.
