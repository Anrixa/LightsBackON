# QA89–QA92 — Correlated tablet feedback and navigation hardening batch

Baseline: `e85395fd8b3c2665a7b3a7dab57586be9e765997` (post-QA88).

| Phase | Scope | PR |
| --- | --- | --- |
| QA89 | Block unsolicited/unsequenced replies and modernize legacy QA67/70/72/74/81 fixtures | #93 |
| QA90 | Track only this tablet's own sends on the shared intent outbox | #94 |
| QA91 | Guard against reentrant nested `sent` signals using exact expected outbox sequence | #95 |
| QA92 | Reject invalid and pre-snapshot tab callbacks without breaking pending replies or focus | #96 |

The changes are UI-only. Grid authority, power topology, repair state, mission content, save/reward logic, host transports, Steam and licensed assets were not modified.

## Gates
Each phase requires exact source-head Linux and Windows CI, pinned Godot 4.7.2; Windows release EXE/PCK export and headless smoke; QA51 resource lifetime probes. Merge commits require postmerge main CI. This file does not assert these future runs have succeeded; consult the linked PR and GitHub Actions checks as evidence.

## Pending physical/human acceptance
- Issue #51: physical Windows GPU steady-state memory, P95 frame time, controller and long-session UX.
- UX01/V09: real-controller accessibility, first-repair discoverability, ten actual playable slice sessions.
- F02/F06: two real Windows PCs, distinct networks/accounts and Steam transport certification.
- No Steam account, store/publishing, paid activity or licensed media was touched.

## Hours / classification
No reliable human or machine work-hours were captured; do not invent them. These QA fixes do not promote the original milestone status ceilings (`CLOUD_VERIFIED` remains where real hardware and testers are needed).
