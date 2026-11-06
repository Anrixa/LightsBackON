# QA84–QA87 — Offline tablet reliability batch

Baseline: `0aabf2b942c19fd74ccf48f30a4cd53db351520c` (post QA83). No new product scope or design decision.

| Phase | Change | PR |
| --- | --- | --- |
| QA84 | Idempotent modal close; prevent duplicate lifecycle and focus stealing | #88 |
| QA85 | Match response action/target/session before consuming a sequence | #89 |
| QA86 | Clear obsolete action outcome when a new request begins | #90 |
| QA87 | Require an active Network visit for Ping/Inspect dispatch and feedback | #91 |

All fixes remain UI/presentation-only and keep grid authority, durable saves, content revisions, Steam transport, protocols and licensing unchanged.

## Validation boundary
Each PR requires `bash tools/run_tests.sh` on GitHub Linux and Windows, Windows export/headless smoke, and QA51 lifetime probes; post-merge `main` CI must pass.

## Outstanding
- Physical Windows gamepad, controller focus feel and UX01/V09 human accessibility review.
- GPU target-class performance (P95, RAM/VRAM), real game presentation.
- F02/F06 Steam transport with two independent PCs/networks/accounts.
- Publishing and store operations are not authorized.
- #51 resource-monitoring follow-up stays open; passing isolate probes does not resolve it.

## Hours and decisions
Automated implementation and CI were executed through GitHub tools; no human time-sheet hours were captured. Do not invent hours. No expansion/public-demo approval was made.
