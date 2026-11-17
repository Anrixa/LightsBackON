# CT-L2/C08 — Split Supply (original blueprint implementation candidate)

- Date: 17 November 2026.
- Authority: original repository `docs/blueprint/Lights-Back-On-Development-Blueprint-v1.0.pdf`, pp.18, 20–21, read from the page content streams.
- Main baseline: `5cd24e75e8cdaf805d3ce4bb10cbf3e1d327c8d3` (merged C07).
- Work branch: `task/CTL2-C08-split-supply-blueprint`.
- Status: **CLOUD_VERIFIED headless logic candidate**, source-aligned to original sheet; not physical/release/production certified. Implementation commit `7af2e943a06017d7f50df93cd7981b7129d577ef` passed Linux/Windows CI #43999774167. Final PR-head documentation-only verification and post-merge CI must still pass.

## Authored host semantics

A (18 PU) supplies Canal west (LAUNDRETTE5, DINER4, ROW_HOUSES4; 13/14 feeder). B (16 PU) starts offline, east DEPOT4, COLD_STORE5, PUMP_KIOSK3 (12/14 feeder) disconnected. Independent A-to-JE tie has 14 PU and starts open.

On the approved solution, shed laundrette and row houses (9 PU), keep diner4, connect A tie to supply east12 (A source16/18), sustain depot power for 100 consecutive 10 Hz ticks, and unlock B cabinet. Inspect and repair B under isolated JE using the supplied B relay. **Open A tie before closing B-to-JE feeder.** Only then restore west loads, leaving A13/18 and B12/16.

A new optional `grid_sources` mission field supports multiple authorized permanent sources while retaining legacy `grid_source`. A source over its own PU limit is not accepted as valid C08 depot access or final verification supply. The existing authoritative graph validator refuses any attempt to close B feeder while A tie energizes JE, atomically and without a one-tick phantom dual feed.

The optional `DINER_UNINTERRUPTED` bonus is monitored after **each processed host command** as well as every 10 Hz host tick: even a power-off and recovery between ticks permanently loses the bonus but never prevents six-load completion. Its conditional one-boolean durable receipt is validated before restore; C01–C07 checkpoint shapes remain unchanged.

No new real-physics electrical claims, client-side power authority, speculative physical Canal Yard positions, portable source or scene-certified interaction targets were added.

## First hosted test iteration (failed, corrected before certification)
- [PR #164 CI #43999444015](https://github.com/Anrixa/LightsBackON/actions/runs/43999444015): Linux reported **625 passed, 10 failed, 45,801 assertions**. The common root cause was `SessionHost.configure` validating switches only against nodes; both authored C08 tie switches target edges, so they were rejected as BAD_SWITCH and the downstream trace/tests failed. Existing C01–C07 solution replays remained SOLVED, Python parity MATCH.
- Correction: permit authored edge targets only for existing whitelisted PowerGrid.SETTABLE boolean fields, still rejecting capacity mutation and invalid/missing IDs. Added a same-tick depot glitch reset for continuous cabinet access and two more regressions. This is NOT a passing CI receipt.

## Verified host and export evidence (source commit `7af2e943a06017d7f50df93cd7981b7129d577ef`)

[GitHub Actions #43999774167](https://github.com/Anrixa/LightsBackON/actions/runs/43999774167): **Linux SUCCESS, Windows SUCCESS** on the tested PR source.

| Gate | Linux | Windows |
|---|---|---|
| Godot suite | 637 PASS / 0 FAIL / 45,948 assertions | 637 PASS / 0 FAIL / 45,948 assertions |
| Content validator | 85 JSON files / 0 errors | 85 JSON files / 0 errors |
| All eight solution traces | C01–C08 SOLVED | C01–C08 SOLVED |
| C08 host trace | 277 ticks / 35 steps / SOLVED | 277 ticks / 35 steps / SOLVED |
| Reference hash parity | MATCH: 32 runs, 246 commands, 10 rejection cases | MATCH: same |
| Windows export/QA57 | N/A | Godot script UIDs PASS, Windows export PASS, headless exported smoke PASS, QA57 EXE/PCK source pin PASS |

The Windows CI build uses a synthetic PR merge SHA `a06e3ea829e95bae467233a46d8290352b3a58eb` for its export; the tested PR source SHA above is the implementation authority. This is not a live GPU, controller, audio or two-machine Steam test. A subsequent evidence-only head update must still pass on its own exact SHA before merge.

## Tests authored (executed on the tested source)

`tests/integration/test_CTL2_C08_split_supply.gd` checks baseline/source/feeder/demand, exact 3-star known solution, timed access latch, interrupted timer reset, source-overload abuse, atomic dual-supply refusal, one-tick break-before-make transition, same-tick DINER interruption bonus loss, durable save validation and tampering rejection, bad source and optional definitions, two-player host replay and legacy C01–C07 save shapes.

All code-level Linux/Windows gates above were observed PASS on implementation SHA. The **final** PR-head CI (after this evidence update) remains required for merge. QA51 lifetime probes apply to scene/resource changes; this C08 work adds headless contract data and mission/host rules without new scene nodes or runtime resource lifecycle ownership. Do not substitute this CI for physical hardware or human acceptance.

## CT-L2 consolidated gate report

See [CTL2-GATE.md](CTL2-GATE.md) for the C05–C08 gate, original C02–C06 fidelity holds, and authoritative pass/fail boundaries.

## Certification limits and corrective track

C02–C06 retain `HOLD_CONFIRMED_MISMATCH`; the recorded defects in `docs/evidence/CTL2-BLUEPRINT-RECONCILIATION.md` are independently tracked for corrective implementation (not waived by C08's success). C07 and C08 source-aligned headless implementations still require physical level/controller/UX validation. Official CT05 remains NOT_STARTED behind CT04; F02/F06 Steam two-network tests and V09/D08 human acceptance remain unqualified. No existing saves have been migrated or deleted.

## Resume notes

Run exact-final-PR-head Linux and Windows CI after this evidence/tracker commit. If both PASS, merge PR #164 with a merge commit and verify the merged-main push CI; log the merge SHA in PR discussion. Next, undertake dedicated C02→C06 original-blueprint corrections in separately reviewable phases (C02 first), each with a new solution replay and falsification tests. Do not promote provisional C02–C06 based on historical CI; original-blueprint fidelity remains HOLD.
