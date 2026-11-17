# CT-L3 — Hill Road C09–C12 source closeout

Source authority: Development Blueprint v1.0 pp.18,20–21 and the preserved contract specifications.

This phase reconciles previously stale CT-L3 tracking, expands the blueprint drift guard from C09–C10 to C09–C12 and adds negative Python regressions. It does **not** add physical content or certify original gameplay.

| Contract | Final PR | Exact-head dual-OS CI | Merged main | Independent merged-main CI |
| --- | --- | --- | --- | --- |
| C09 | [#171](https://github.com/Anrixa/LightsBackON/pull/171) | [#44137702068](https://github.com/Anrixa/LightsBackON/actions/runs/44137702068) SUCCESS | \`13223b7472a9720a8e2630a497ee02452fb407e0\` | [#44138557595](https://github.com/Anrixa/LightsBackON/actions/runs/44138557595) SUCCESS |
| C10 | [#173](https://github.com/Anrixa/LightsBackON/pull/173) | [#44141631975](https://github.com/Anrixa/LightsBackON/actions/runs/44141631975) SUCCESS | \`7eda69f1b80863d5f82a0cab928d526251b051b1\` | [#44142259928](https://github.com/Anrixa/LightsBackON/actions/runs/44142259928) SUCCESS |
| C11 | [#174](https://github.com/Anrixa/LightsBackON/pull/174) | [#44151282829](https://github.com/Anrixa/LightsBackON/actions/runs/44151282829) SUCCESS | \`b29a68c0b5255b71febb2520353c836aeb51d622\` | [#44152056131](https://github.com/Anrixa/LightsBackON/actions/runs/44152056131) SUCCESS |
| C12 | [#175](https://github.com/Anrixa/LightsBackON/pull/175) | [#44155478774](https://github.com/Anrixa/LightsBackON/actions/runs/44155478774) SUCCESS | \`9e141bffab6e5525661c9c3c18688cae64b38ca8\` | [#44156570604](https://github.com/Anrixa/LightsBackON/actions/runs/44156570604) PENDING AT SOURCE AUTHORING |

C12 final PR tested 712 Godot tests / 0 failed / 52,386 assertions per OS, C01–C12 SOLVED, C12 353 ticks / 70 steps, Python/Godot reference MATCH. C11 final and merged-main tested 699 / 0 / 51,744 per OS, C11 287 ticks / 42 steps. Earlier C09/C10 CI receipts are in their individual evidence files.

## Mandatory gate before closeout merge

- Exact **closeout PR-head** Linux + Windows successful CI, all C01–C12 host solutions, reference parity, content gate and Windows QA57 EXE/PCK headless export/smoke.
- **Fresh independent closeout merged-main dual-OS CI** after merge; only then mark source closeout verified.
- The Python drift checker is static; it does **not** replace replay, load protection or headless physics verification.
- Source qualification ceiling: \`SOURCE_ALIGNED_HEADLESS_CANDIDATE\`, never "physical" or "production" certification.

## Physical and release acceptance remains on HOLD

Full Hill Road authored level geometry, sockets/cables, roof/ground route traversal, generator controls, stage/beacon/light positions, radio subtitle and controller UX, human playthroughs, actual target GPU P95/memory, historical shipped-save compatibility and real two-network Steam F02/F06 remain unqualified. Canonical CT02/CT05/CT06 and production cannot be promoted by this source track. No saves, release channels, GPU captures or Steam credentials modified.
