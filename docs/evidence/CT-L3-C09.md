# CT-L3/C09 — Wind Warning source development evidence

- Original-source authority: Development Blueprint v1.0 pp.18,20–21. C09–C12 constants transcribed directly from blueprint; never derived from the previous districts.
- Branch: `task/CT-L3-C09-wind-warning`; base `main` `2e5dd7adae05cdab6663dcea560290a70a441999` (merged-main [CI #44133514433](https://github.com/Anrixa/LightsBackON/actions/runs/44133514433): SUCCESS).
- **Gate: SOURCE_IMPLEMENTED_CI_PENDING.** No CI or physical certification is claimed by this implementation-only record.

## Authored candidate
- GRID28 / GEN6, feeders14 each, west13 and east12, six required GRID services25.
- WEST failed fuse; EAST broken trunk. Host-approved roof-entry/ground-alley access routes, with range checks before repairs. No invented electrical roof bypass.
- Mission-relative 10Hz wind warning at 600 ticks; roof ENTRY closed at 900–1300 inclusive; at 1301 it reopens. Ground always available and roof safe-return authorized during closure. Wind never mutates repaired equipment.
- 200-tick longer ground traversal is an **unmeasured target** for later physical navigation playtesting, not fabricated headless travel delay.
- Optional sheltered GEN-powered work light2 latches after100 consecutive ticks. No mandatory deadline; missing the bonus cannot block six-service restoration, safe stow or extraction.
- Conditional checkpoint and canonical snapshot wind state; prior C01–C08 save key shapes untouched.
- The C10–C12 blueprint authority is transcribed in `docs/design/CT-L3-original-contract-sheets.json`, **planning only**, without claiming implementations.

## Required checks
1. Implement and run negative/boundary, save, solo/group, supply and route tests, including C01–C08 regressions.
2. Exact-head Linux+Windows CI and C01–C09 solution traces, Python reference parity, QA57 Windows export/headless manifest checks.
3. Independent merge and merged-main CI before `SOURCE_ALIGNED_HEADLESS_CANDIDATE` can be recorded.
4. Physical Hill Road routing, actual 20-second detour comparison, controller/human, target-GPU, old saves, Steam F02/F06 and official CT02/CT05/CT06 remain HOLD.
